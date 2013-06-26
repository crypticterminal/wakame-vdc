# -*- coding: utf-8 -*-

module Dcmgr::VNet::Netfilter::NetfilterAgent
  def self.included klass
    klass.class_eval do
      include Dcmgr::VNet::Netfilter::Chains
    end
  end

  def init_vnic(vnic_id, tasks)
    logger.info "Adding chains for vnic '#{vnic_id}'."
    exec vnic_chains(vnic_id).map {|chain| chain.create}
  end

  def destroy_vnic(vnic_id)
    logger.info "Removing chains for vnic '#{vnic_id}'."
    exec vnic_chains(vnic_id).map {|chain| chain.destroy}
  end

  def init_security_group(secg_id, tasks)
    logger.info "Adding security chains for group '#{secg_id}'."
    exec secg_chains(secg_id).map {|chain| chain.create }
    #TODO: Add secg rules to this chain
  end

  def destroy_security_group(secg_id)
    logger.info "Removing security chains for group '#{secg_id}'."
    exec secg_chains(secg_id).map {|chain| chain.destroy }
  end

  def init_isolation_group(isog_id, tasks)
    logger.info "Adding isolation chains for group '#{isog_id}'."
    exec isog_chains(isog_id).map {|chain| chain.create}
    #TODO: Add isolation rules for all vnics in the isog (secg in reality) to this chain
  end

  def destroy_isolation_group(isog_id)
    logger.info "Removing isolation chains for group '#{isog_id}'."
    exec isog_chains(isog_id).map {|chain| chain.destroy}
  end

  # Split this in security group and isolation group?
  def set_vnic_security_groups(vnic_id,secg_ids)
    logger.info "Setting security groups of vnic '#{vnic_id}' to [#{secg_ids.join(",")}]."
    exec [
      vnic_l2_iso_chain(vnic_id).flush,
      vnic_l3_iso_chain(vnic_id).flush,
      vnic_l3_secg_chain(vnic_id).flush
    ]

    exec secg_ids.map { |secg_id|
      [vnic_l2_iso_chain(vnic_id).add_jump(secg_l2_iso_chain(secg_id)),
      vnic_l3_iso_chain(vnic_id).add_jump(secg_l3_iso_chain(secg_id)),
      vnic_l3_secg_chain(vnic_id).add_jump(secg_l3_rules_chain(secg_id))]
    }.flatten
  end

  def update_sg_rules(secg_id,tasks)
  end

  def update_isolation_group(group_id,tasks)
    logger.info "Updating vnics in isolation group '#{group_id}'."
  end

  def remove_all_chains
    prefix = Dcmgr::VNet::Netfilter::Chains::CHAIN_PREFIX
    logger.info "Removing all chains prefixed by '#{prefix}'."
    system("for i in $(ebtables -L | grep 'Bridge chain: #{prefix}' | cut -d ' ' -f3 | cut -d ',' -f1); do ebtables -X $i; done")
    system("for i in $(iptables -L | grep 'Chain #{prefix}' | cut -d ' ' -f2); do iptables -F $i; iptables -X $i; done")
  end

  private
  def exec(cmds)
    #TODO: Make vebose commands options
    cmds = [cmds] unless cmds.is_a?(Array)
    puts cmds.join("\n")
    system cmds.join("\n")
  end

end
