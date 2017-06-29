#!/bin/bash
function create_admin_networking () {
    echo ""
    echo "Creating admin network for public use (NOT FOR LOCAL ACCOUNTS)  ..."
    echo "  Note: This is typically a one-time need ..."
    echo ""
    tenant=$(openstack project list -f csv --quote none | grep admin | cut -d, -f1)
    echo "Please enter the public network that will be used for floating IP's in the following format: 10.245.126"
    read -r public_network
    #public_network=10.245.126
    openstack network create --project "${tenant}" --external --provider-network-type flat --provider-physical-network physnet1 --share public
    #neutron net-create public --tenant-id "${tenant}" --router:external --provider:network_type flat --provider:physical_network physnet1 --shared
    #if segmented network{vlan,vxlan,gre}: --provider:segmentation_id ${segment_id}
    openstack subnet create --project "${tenant}" --subnet-range "${public_network}".0/24 --allocation-pool start="${public_network}".15,end="${public_network}".249 --dns-nameserver 10.245.0.10 --no-dhcp --gateway "${public_network}".253 --network public public_subnet
    #neutron subnet-create public "${public_network}".0/24 --tenant-id "${tenant}" --allocation-pool start="${public_network}".15,end="${public_network}".249 --dns-nameserver 10.245.0.10 --disable-dhcp --gateway="${public_network}".253
    # if you need a specific route to get "out" of your public network: --host-route destination=10.0.0.0/8,nexthop=10.1.10.254
}


function create_networking () {
    echo ""
    echo "Creating private networking..."
    echo "  Note: This is what can be used in everyone tenant accounts...."
    echo ""
    openstack network create --project "${tenant}" private
    openstack subnet create --project "${tenant}" --subnet-range 192.168.100.0/24 --dns-nameserver 10.245.0.10 --no-dhcp --network private private_subnet
    openstack router create --enable --project "${tenant}" pub-router
    #neutron router-create pub-router --tenant-id "${tenant}"

    openstack router set pub-router --external-gateway public
    #neutron router-gateway-set pub-router public

    openstack router add subnet pub-router private_subnet
    #neutron router-interface-add pub-router private

    # Adjust the default security group.  This is not good practice
    #default_group=$(neutron security-group-list | awk '/ default / {print $2}' | tail -n 1)
    default_group=$(openstack security group list | grep "${tenant}" | awk '{print $2}')
    openstack security group rule create "${default_group}" --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0
    openstack security group rule create "${default_group}" --protocol tcp --dst-port 80:80 --remote-ip 0.0.0.0/0
    openstack security group rule create "${default_group}" --protocol tcp --dst-port 443:443 --remote-ip 0.0.0.0/0
    openstack security group rule create "${default_group}" --protocol icmp
}


function tmp () {
  echo "hello"
}


function one_time () {
    echo ""
    echo "One time install... (openstack clients, cirros, flavors)"
    echo ""
    pip install python-openstackclient
    pip install python-neutronclient
    wget http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
}

function setup_OpenStack () {
    openstack image create --disk-format qcow2 --container-format bare --public --file cirros-0.3.5-x86_64-disk.img  cirros
    openstack flavor create --id 1 --ram 512 --disk 1 --vcpus 1 m1.tiny
    openstack flavor create --id 2 --ram 2048 --disk 20 --vcpus 1 m1.small
    openstack flavor create --id 3 --ram 4096 --disk 40 --vcpus 2 m1.medium
    openstack flavor create --id 4 --ram 8192 --disk 80 --vcpus 4 m1.large
    openstack flavor create --id 5 --ram 16384 --disk 160 --vcpus 8 m1.xlarge
}

function deploy_instance () {
    echo ""
    echo "Deploying instances ..."
    echo ""
    INSTANCE_NAME=tmp
    openstack --insecure keypair create tmp_keypair > ~/tmp_keypair
    chmod 600 ~/tmp_keypair
    openstack server create --key-name tmp_keypair --image cirros --flavor m1.tiny --network private $INSTANCE_NAME
    FLOATING_IP=$(openstack floating ip create public |grep floating_ip_address | awk '{print $4}')
    openstack server add floating ip $INSTANCE_NAME "$FLOATING_IP"
    echo "******************************"
    echo "Floating IP is: [$FLOATING_IP]"
    echo "******************************"
    echo "ssh -i ~/tmp_keypair cirros@$FLOATING_IP"
    sleep 5
    ssh -i ~/tmp_keypair cirros@"$FLOATING_IP"
}

function usage () {
    echo ""
    echo "Missing paramter. Please Enter one of the following options"
    echo ""
    echo "Usage: $0 {Any of the options below}"
    echo ""
    echo "  "
    echo "  one_time"
    echo "     Sets up openstack clients and downloads cirros"
    echo "  setup_OpenStack"
    echo "     Creates openstack flavors and uploads cirros image"
    echo "  create_admin_networking"
    echo "     Creates the public network for floating IP's"
    echo "  create_networking"
    echo "     Creates private network"
    echo "  deploy_instance"
    echo "     Creates keypair, cirros instance, and attempts to ssh into it."
    echo ""
    echo ""
    echo "  deploy (does above without one_time)"
    echo "     Executes:"
    echo "       setup_OpenStack "
    echo "       create_admin_networking "
    echo "       create_networking "
    echo "       deploy_instance "
    echo ""
    echo ""
}

function main () {
    echo ""
    echo " Setup openstack"
    echo ""
    echo ""

    source /etc/kolla/admin-openrc.sh
    if [ -z "$1" ]; then
        usage
        exit 1
    fi

    if [ "$1" == "deploy" ]; then
        setup_OpenStack
        create_admin_networking
        create_networking
        deploy_instance
    else
        case $1 in
        "one_time")
            one_time
            ;;
        "setup_OpenStack")
            setup_OpenStack
            ;;
        "create_networking")
            create_networking
            ;;
        "deploy_instance")
            deploy_instance
            ;;
        "tmp")
            tmp
            ;;
        "create_admin_networking")
            create_admin_networking
            ;;
        *)
            usage
            exit 1
        esac
    fi
}

main "$1"
