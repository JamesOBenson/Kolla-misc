#!/bin/bash
SLEEP=5
ANSIBLE_VERSION=2.5.*
#RACK=6
#KOLLA_VERSION=6.1.0
touch .kolla_configs

# shellcheck disable=SC1091
source .kolla_configs

if  [ -z "$RACK" ]; 
 then
    echo "What rack do you want to work on?"
    read -r RACK
    echo "RACK=$RACK" >> .kolla_configs
  else 
    RACK=$RACK;
fi
KollaAnsible_INSTALLED="$(pip list --format=columns | grep kolla-ansible  | awk '{print $2}')"
Kolla_Installed="$(pip list --format=columns | grep "kolla " | awk '{print $2}')"
#echo "KollaAnsible_INSTALLED= " $KollaAnsible_INSTALLED
#echo "Kolla_Installed= " $Kolla_Installed

# Make sure kolla version is correct in config file
if [ "$KollaAnsible_INSTALLED" == "$Kolla_Installed" ];
then
  KOLLA_VERSION="${Kolla_Installed}" #:1:-1}"
#  echo "KOLLA_VERSION=$KOLLA_VERSION"
  sed -i -e "s/.*KOLLA_VERSION.*/KOLLA_VERSION=$KOLLA_VERSION/" -e "KOLLA_VERSION=$KOLLA_VERSION" .kolla_configs
fi

# Make sure Kolla and Kolla ansible version match
if [ "$KollaAnsible_INSTALLED" != "$Kolla_Installed" ];
then
  echo "Please verify that you have both Kolla and Kolla-ansible installed"
  echo "and that the version match: pip list --format=columns  grep 'kolla'"
fi

# Make sure Kolla Version is in file
if ! grep -R "KOLLA_VERSION" .kolla_configs > /dev/null;
then
  echo "KOLLA_VERSION=$KOLLA_VERSION" >>.kolla_configs
fi

echo "$INSTALLED"
if  [ -z "$KOLLA_VERSION" ]; 
then
  echo "What version of Kolla?"
  options=("6.1.0")
  select kolla in "${options[@]}"
  do
    case $kolla in
        "6.1.0" ) 
          echo "KOLLA_VERSION=6.1.0" >> .kolla_configs
          KOLLA_VERSION=6.1.0;break;;
        * ) echo "Invalid option";;
    esac
  done
fi

if  [ -z "$OPERATING_SYSTEM" ];
then
  echo "What docker OS would you like to use?"
  options=("ubuntu")
  select OPERATING_SYSTEM in "${options[@]}"
  do
    case $OPERATING_SYSTEM in
        "ubuntu" )
           echo "OPERATING_SYSTEM=ubuntu" >> .kolla_configs
           OPERATING_SYSTEM=ubuntu;break;;
    esac
  done
fi

###############
# DO NOT MODIFY 
###############
INVENTORY_FILE="templates/multinode"$RACK

function update_globals () {
  sed "s/{KOLLA_VERSION}/$KOLLA_VERSION/" templates/globals.yml.template > globals.yml
  sed -i "s/{RACK}/$RACK/" globals.yml
  sed -i "s/{OPERATING_SYSTEM}/$OPERATING_SYSTEM/" globals.yml
  if [ "$OPERATING_SYSTEM" == "ubuntu" ]; then
    sed -i "s/{INSTALLATION_TYPE}/source/" globals.yml
  elif [ "$OPERATING_SYSTEM" == "centos" ]; then
    sed -i "s/{INSTALLATION_TYPE}/binary/" globals.yml
  fi 
  cp globals.yml /etc/kolla/globals.yml
  rm globals.yml
}

function Reboot () {
  ansible-playbook -i "$INVENTORY_FILE"  main.yml --tags "Reboot"
}

function one_time () {
  echo ""
  echo "<One_time>"
  echo ""
  echo " Installing all pre-req's to get Kolla deployment up and running"
  echo "    Also sets up interfaces defined in tmp"
  apt update
  apt install -y python-pip
  pip install -U pip
  apt install -y python-dev libffi-dev gcc libssl-dev
  pip install -U ansible==$ANSIBLE_VERSION
  pip uninstall -U Jinja2 
  pip install -U Jinja2 #==2.8
  #pip install -U git+https://github.com/openstack/kolla-ansible.git@stable/ocata
  pip install kolla-ansible==$KOLLA_VERSION
  curl -sSL https://get.docker.io | bash
#  pip install kolla==$KOLLA_VERSION
  #pip install -U git+https://github.com/openstack/kolla.git@stable/ocata
  cp -r /usr/local/share/kolla-ansible/etc_examples/kolla /etc/kolla/
  pip install -U python-openstackclient
}

function settings () {
  echo ""
  echo "<settings>"
  echo ""
  echo " Copying default settings and moving YOUR global file to /etc/kolla"
  echo ""
  cp -r /usr/local/share/kolla-ansible/etc_examples/kolla /etc/kolla/
#cp /usr/local/share/kolla-ansible/ansible/inventory/* .
  update_globals
}

function bootstrap () {
  echo ""
  echo "<bootstrap>"
  echo ""
  echo " Sets up/configures:"
  echo "   - purges LXD/LXC (oneTime)"
  echo "   - SSH via root (oneTime)"
  echo "   - Generates appropiate Interfaces/reboots"
  echo "   - sets up python"
  echo "   - KOLLA GEN-PASSWORD"
  echo "   - KOLLA BOOTSTRAP"
  echo ""
  echo " Sets up ceph, kolla bootstrap, and genpwd"
  echo ""
  sleep 5
  #ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "oneTime" -u ubuntu --extra-vars='{"CIDR": "0.0.0.0"}'
  if [ "$OPERATING_SYSTEM" == "ubuntu" ]; then
    ansible -i "$INVENTORY_FILE" -m apt -a "name=python state=present" --become all -u ubuntu -e ansible_python_interpreter=/usr/bin/python3
    sleep 2
    ansible-playbook -i "$INVENTORY_FILE"  main.yml --tags "oneTime" -u ubuntu --extra-vars='{"CIDR": "0.0.0.0"}'
    sleep 2
    ansible-playbook -i "$INVENTORY_FILE"  main.yml --tags "generate_public_interfaces" -u ubuntu
    sleep 2
  fi

  if [ "$OPERATING_SYSTEM" == "centos" ]; then
    ansible -i "$INVENTORY_FILE" -m yum -a "name=python state=present" --become all -u centos -e ansible_python_interpreter=/usr/bin/python
    ansible-playbook -i "$INVENTORY_FILE"  main.yml --tags "oneTime" -u centos --extra-vars='{"CIDR": "0.0.0.0"}'
    ansible-playbook -i "$INVENTORY_FILE"  main.yml --tags "generate_public_interfaces" -u centos
  fi

  #ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "generate_public_interfaces" -u ubuntu
#  ansible -i "$INVENTORY_FILE" -m shell -a "parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP 1 -1" storage 
  #ansible -i "$INVENTORY_FILE" -m shell -a "sgdisk --zap-all --clear --mbrtogpt /dev/sdb; sgdisk --zap-all --clear --mbrtogpt /dev/sdc; sgdisk --zap-all --clear --mbrtogpt /dev/sdd; sgdisk --zap-all --clear --mbrtogpt /dev/sde" storage

  #ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vasrs='{"CIDR":"0.0.0.0"}'
  #ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "ceph" -u ubuntu --extra-vars='{"CIDR": "0.0.0.0"}'
  kolla-genpwd
  kolla-ansible -i "$INVENTORY_FILE" bootstrap-servers
  kolla-ansible certificates
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "destroy_public_interfaces" --extra-vars='{"CIDR":"1.0.0.0"}'
  #ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vars='{"CIDR":"0.0.0.0"}'
}

function destroy () {
  echo ""
  echo "<destroy>"
  echo ""
  echo "- Killing VM's"
  echo "- kolla-ansible destroy"
  echo "- Destroy ceph volumes"
  echo "- optional: delete images on nodes"
  echo ""
  echo -e "$(date) \\t -- \\t Kolla $KOLLA_VERSION will be DESTROYED on Rack $RACK" >> deploy_history.log
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "kill_VMs" --extra-vars='{"CIDR":"0.0.0.0"}'
  kolla-ansible -i "$INVENTORY_FILE" destroy --yes-i-really-really-mean-it
#  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "ceph" --extra-vars='{"CIDR":"0.0.0.0"}'
#  ansible -i $INVENTORY_FILE -m shell -a "parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP 1 -1" storage
#  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vars='{"CIDR":"0.0.0.0"}'
  echo "Do you with to delete ALL containers on hosts too?"
  select yn in "Yes" "No"; do
    case $yn in
        Yes ) ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "kill_dmi" --extra-vasrs='{"CIDR":"0.0.0.0"}'; break;;
        No ) break;;
        * ) echo "Invalid option";;
    esac
  done
  rm .kolla_configs
}

function prechecks () {
  echo ""
  echo "<prechecks>"
  echo ""
  echo " Kolla prechecks and pull images local"
  echo ""
  kolla-ansible prechecks -i  "$INVENTORY_FILE"
  sleep "$SLEEP"
  kolla-ansible pull -i "$INVENTORY_FILE"
  sleep "$SLEEP"
}

function deploy () {
  echo ""
  echo "<deploy>"
  echo ""
  echo -e "$(date) \\t -- \\t Kolla $KOLLA_VERSION will be deployed on Rack $RACK USING $OPERATING_SYSTEM DOCKER IMAGES" >> deploy_history.log
  time kolla-ansible deploy -i "$INVENTORY_FILE" #-vv
  sleep "$SLEEP"
}

function post_deploy () {
  kolla-ansible post-deploy
  grep OS_PASSWORD /etc/kolla/admin-openrc.sh
  wget http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
  ./scripts/setup_networking.sh deploy
}

function clear_configs () {
  rm .kolla_configs
}

function usage () {
    echo ""
    echo "Missing paramter. Please Enter one of the following options"
    echo ""
    echo "Usage: $0 {Any of the options below}"
    echo ""
    echo ""
    echo "  one_time"
    echo "    Installs necessary components for deployment node"
    echo ""
    echo "  settings"
    echo "    Moves local global.yml to /etc/kolla/global.yml"
    echo ""
    echo "  Reboot"
    echo "    Reboot all nodes"
    echo ""
    echo "  bootstrap"
    echo "    Fixes interfaces file for bridges"
    echo "    bootstraps the servers"
    echo "    generates passwords"
    echo ""
    echo "  prechecks"
    echo "    runs the prechecks"
    echo "    pulls images based off of globals file"
    echo "    "
    echo "  deploy"
    echo "    Destroy public interfaces besides controllers"
    echo "    Deploy"
    echo ""
    echo "  post_deploy"
    echo "    runs the post-deploy and cat's out admin password"
    echo ""
    echo "  destroy"
    echo "    destroys the evironment and wipes ceph"
    echo ""
    echo "  deploy_all"
    echo "    precheck"
    echo "    deploy"
    echo "    post_deploy"
    echo ""
    echo ""
    echo ""
    kolla_external_vip_address=$(awk -v FS="kolla_external_vip_address: " 'NF>1{print $2}'  /etc/kolla/globals.yml)
    kolla_external_fqdn=$(awk -v FS="kolla_external_fqdn: " 'NF>1{print $2}'  /etc/kolla/globals.yml)
    admin_pass=$(awk -v FS="export OS_PASSWORD=" 'NF>1{print $2}' /etc/kolla/admin-openrc.sh)
    echo -e "\\033[33;7mCURRENTLY SET TO DEPLOY KOLLA $KOLLA_VERSION TO RACK $RACK USING $OPERATING_SYSTEM DOCKER IMAGES ### \\033[0m"
    echo -e "\\033[33;7mPlease try to log into $kolla_external_vip_address or $kolla_external_fqdn with username admin and password: $admin_pass  \\033[0m"
    echo ""
    echo " To clear configs: clear_configs"
}

function main () {
    echo ""
    echo " Setup openstack"
    echo ""
    echo ""

    if [ -z "$1" ]; then
        usage
        exit 1
    fi

    if [ "$1" == "deploy_all" ]; then
        update_globals
        prechecks
        deploy
        post_deploy

    else
        case $1 in
        "one_time")
            one_time
            ;;
        "settings")
            settings
            ;;
        "bootstrap")
            bootstrap
            ;;
        "prechecks")
            prechecks
            ;;
        "deploy")
            deploy
            ;;
        "post_deploy")
            post_deploy
            ;;
        "destroy")
            destroy
            ;;
        "Reboot")
            Reboot
            ;;
        "update_globals")
            update_globals
            ;;
        "clear_configs")
            clear_configs
            ;;
        esac
    fi
}

update_globals
main "$1"
