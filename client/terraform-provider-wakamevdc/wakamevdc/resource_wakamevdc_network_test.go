package wakamevdc

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"testing"

	"github.com/axsh/wakame-vdc/client/go-wakamevdc"
	"github.com/hashicorp/terraform/helper/resource"
	"github.com/hashicorp/terraform/terraform"
)

const testConfig = `
resource "wakamevdc_network" "nw1" {
	ipv4_network = "10.0.0.0"
	prefix = 24
	network_mode = "l2overlay"
	dc_network_id = "%s"
	display_name = "nw1"
	description = "I am a testing network"
}
`

const testConfigUpdate = `
resource "wakamevdc_network" "nw1" {
	ipv4_network = "10.0.0.0"
	prefix = 24
	network_mode = "l2overlay"
	dc_network_id = "%s"
	display_name = "a new name for me"
	description = "I am a testing network"
}
`

func fetchDCN(name string) (string, error) {
	apiURL, err := url.Parse(os.Getenv("WAKAMEVDC_API_ENDPOINT"))
	if err != nil {
		return "", err
	}

	client := wakamevdc.NewClient(apiURL, nil)

	dcnList, _, err := client.DCNetwork.List(nil, "vnet")
	if err != nil {
		return "", err
	}

	return dcnList.Results[0].ID, nil
}

func TestResourceWakamevdcNetworkFull(t *testing.T) {
	var resourceID string

	dcnID, err := fetchDCN("vnet")
	if err != nil {
		t.Fatalf("Failed to find ID (dcn-xxxx) of \"vnet\" DC Network: %s", err)
	}

	testNetworkCreated := func(s *terraform.State) error {
		rs, network, err := getTerraformResourceAndWakameNetwork(s, "wakamevdc_network.nw1")

		if err != nil {
			return err
		}

		if network.ID != rs.Primary.ID {
			return parameterCheckFailed("id", network.ID, rs.Primary.ID)
		}

		if network.Description != rs.Primary.Attributes["description"] {
			return parameterCheckFailed("description",
				network.Description,
				rs.Primary.Attributes["description"])
		}

		if network.NetworkMode != rs.Primary.Attributes["network_mode"] {
			return parameterCheckFailed("network_mode",
				network.NetworkMode,
				rs.Primary.Attributes["network_mode"])
		}

		if network.DisplayName != rs.Primary.Attributes["display_name"] {
			return parameterCheckFailed("display_name",
				network.DisplayName,
				rs.Primary.Attributes["display_name"])
		}

		prefixStr := strconv.Itoa(network.Prefix)
		if rs.Primary.Attributes["prefix"] != prefixStr {
			return parameterCheckFailed("prefix",
				prefixStr,
				rs.Primary.Attributes["prefix"])
		}

		if network.IPv4Network != rs.Primary.Attributes["ipv4_network"] {
			return parameterCheckFailed("ipv4_network",
				network.IPv4Network,
				rs.Primary.Attributes["ipv4_network"])
		}

		if network.DCNetwork.ID != rs.Primary.Attributes["dc_network_id"] {
			return parameterCheckFailed("dc_network_id",
				network.DCNetwork.ID,
				rs.Primary.Attributes["dc_network_id"])
		}

		resourceID = rs.Primary.ID

		return nil
	}

	testNetworkUpdated := func(s *terraform.State) error {
		rs, network, err := getTerraformResourceAndWakameNetwork(s, "wakamevdc_network.nw1")

		if err != nil {
			return err
		}

		if network.DisplayName != rs.Primary.Attributes["display_name"] {
			return parameterCheckFailed("display_name",
				network.DisplayName,
				rs.Primary.Attributes["display_name"])
		}

		return nil
	}

	testCheckDestroy := func(s *terraform.State) error {
		client := testVdcProvider.Meta().(*wakamevdc.Client)
		_, _, err := client.Network.GetByID(resourceID)
		if _, ok := err.(*wakamevdc.APIError); ok == false {
			return fmt.Errorf("APIError is expected")
		}
		return nil
	}

	resource.Test(t, resource.TestCase{
		PreCheck:     nil,
		Providers:    testVdcProviders,
		CheckDestroy: testCheckDestroy,
		Steps: []resource.TestStep{
			resource.TestStep{
				Config: fmt.Sprintf(testConfig, dcnID),
				Check:  testNetworkCreated,
			},
			resource.TestStep{
				Config: fmt.Sprintf(testConfigUpdate, dcnID),
				Check:  testNetworkUpdated,
			},
		},
	})
}

func getTerraformResourceAndWakameNetwork(s *terraform.State, resourceName string) (*terraform.ResourceState, *wakamevdc.Network, error) {
	rs, ok := s.RootModule().Resources[resourceName]

	if !ok {
		return nil, nil, fmt.Errorf("Not found: %s", resourceName)
	}

	client := testVdcProvider.Meta().(*wakamevdc.Client)

	network, _, err := client.Network.GetByID(rs.Primary.ID)

	return rs, network, err
}
