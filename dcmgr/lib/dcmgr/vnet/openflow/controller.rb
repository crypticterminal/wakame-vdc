# -*- coding: utf-8 -*-

require 'eventmachine'
require 'racket'

class IPAddr
  def to_short
    [(@addr >> 24) & 0xff, (@addr >> 16) & 0xff, (@addr >> 8) & 0xff, @addr & 0xff]
  end
end

module Dcmgr
  module VNet
    module OpenFlow

      class OpenFlowController < Trema::Controller
        include Dcmgr::Logger
        include OpenFlowConstants

        attr_reader :default_ofctl
        attr_reader :switches

        def ports
          switches.first[1].ports
        end

        def local_hw
          switches.first[1].local_hw
        end

        def initialize service_openflow
          @service_openflow = service_openflow
          @default_ofctl = OvsOfctl.new service_openflow.node.manifest.config

          @switches = {}
        end

        def start
          logger.info "starting OpenFlow controller."
        end

        def switch_ready datapath_id
          logger.info "switch_ready from %#x." % datapath_id

          # We currently rely on the ovs database to figure out the
          # bridge name, as it is randomly generated each time the
          # bridge is created unless explicitly set by the user.
          bridge_name = @default_ofctl.get_bridge_name(datapath_id)
          raise "No bridge found matching: datapath_id:%016x" % datapath_id if bridge_name.nil?

          ofctl = @default_ofctl.dup
          ofctl.switch_name = bridge_name

          # There is no need to clean up the old switch, as all the
          # previous flows are removed. Just let it rebuild everything.
          #
          # This might not be optimal in cases where the switch got
          # disconnected for a short period, as Open vSwitch has the
          # ability to keep flows between sessions.
          switches[datapath_id] = OpenFlowSwitch.new(OpenFlowDatapath.new(self, datapath_id, ofctl), bridge_name)
          switches[datapath_id].switch_ready
        end

        def features_reply message
          raise "No switch found." unless switches.has_key? message.datapath_id
          switches[message.datapath_id].features_reply message
          
          @service_openflow.networks.each { |network| network[1].update }
        end

        def insert_port switch, port
          if port.port_info.number >= OFPP_MAX
            # Do nothing...
          elsif port.port_info.name =~ /^eth/
            @service_openflow.add_eth switch, port
          elsif port.port_info.name =~ /^vif-/
            @service_openflow.add_instance switch, port
          elsif port.port_info.name =~ /^t-/
            @service_openflow.add_tunnel switch, port
          else
          end
        end

        def delete_port port
          port.lock.synchronize {
            return unless port.is_active
            port.is_active = false

            if not port.network.nil?
              port.network.remove_port port.port_info.number
              port.network.update
            end

            port.datapath.del_flows port.active_flows
            port.active_flows.clear
            port.queued_flows.clear
            ports.delete port.port_info.number
          }
        end

        def port_status message
          raise "No switch found." unless switches.has_key? message.datapath_id
          switches[message.datapath_id].port_status message
        end

        def packet_in datapath_id, message
          raise "No switch found." unless switches.has_key? datapath_id
          switches[datapath_id].packet_in message
        end

        def vendor message
          logger.debug "vendor message from #{message.datapath_id.to_hex}."
          logger.debug "transaction_id: #{message.transaction_id.to_hex}"
          logger.debug "data: #{message.buffer.unpack('H*')}"
        end

        #
        # Public functions
        #

        def send_udp datapath_id, out_port, src_hw, src_ip, src_port, dst_hw, dst_ip, dst_port, payload
          raw_out = Racket::Racket.new
          raw_out.l2 = Racket::L2::Ethernet.new
          raw_out.l2.src_mac = src_hw
          raw_out.l2.dst_mac = dst_hw
          
          raw_out.l3 = Racket::L3::IPv4.new
          raw_out.l3.src_ip = src_ip
          raw_out.l3.dst_ip = dst_ip
          raw_out.l3.protocol = 0x11
          raw_out.l3.ttl = 128

          raw_out.l4 = Racket::L4::UDP.new
          raw_out.l4.src_port = src_port
          raw_out.l4.dst_port = dst_port
          raw_out.l4.payload = payload

          raw_out.l4.fix!(raw_out.l3.src_ip, raw_out.l3.dst_ip)

          raw_out.layers.compact.each { |l|
            logger.debug "send udp: layer:#{l.pretty}."
          }

          send_packet_out(datapath_id, :data => raw_out.pack.ljust(64, "\0"), :actions => Trema::ActionOutput.new( :port => out_port ) )
        end

        def send_arp datapath_id, out_port, op_code, src_hw, src_ip, dst_hw, dst_ip
          raw_out = Racket::Racket.new
          raw_out.l2 = Racket::L2::Ethernet.new
          raw_out.l2.ethertype = Racket::L2::Ethernet::ETHERTYPE_ARP
          raw_out.l2.src_mac = src_hw.nil? ? '00:00:00:00:00:00' : src_hw
          raw_out.l2.dst_mac = dst_hw.nil? ? 'FF:FF:FF:FF:FF:FF' : dst_hw
          
          raw_out.l3 = Racket::L3::ARP.new
          raw_out.l3.opcode = op_code
          raw_out.l3.sha = src_hw.nil? ? '00:00:00:00:00:00' : src_hw
          raw_out.l3.spa = src_ip.nil? ? '0.0.0.0' : src_ip
          raw_out.l3.tha = dst_hw.nil? ? '00:00:00:00:00:00' : dst_hw
          raw_out.l3.tpa = dst_ip.nil? ? '0.0.0.0' : dst_ip

          raw_out.layers.compact.each { |l|
            logger.debug "ARP packet: layer:#{l.pretty}."
          }

          send_packet_out(datapath_id, :data => raw_out.pack.ljust(64, "\0"), :actions => Trema::ActionOutput.new( :port => out_port ) )
        end

      end


      class OpenFlowForwardingEntry
        attr_reader :mac
        attr_reader :port_no

        def initialize mac, port_no
          @mac = mac
          @port_no = port_no
        end

        def update port_no
          @port_no = port_no
        end
      end
      
      class OpenFlowForwardingDatabase
        def initialize
          @db = {}
        end

        def port_no_of mac
          dest = @db[mac]

          if dest
            dest.port_no
          else
            nil
          end
        end

        def learn mac, port_no
          entry = @db[mac]

          if entry
            entry.update port_no
          else
            @db[new_entry.mac] = ForwardingEntry.new(mac, port_no)
          end
        end
      end

    end
  end
end
