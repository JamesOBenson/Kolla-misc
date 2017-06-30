#!/bin/bash
SLEEP=5
#RACK=6
#KOLLA_VERSION=4.0.0
touch .kolla_configs
source .kolla_configs

if  [ -z "$RACK" ]; 
 then
    echo "What rack do you want to work on?"
    read RACK
    echo "RACK=$RACK" >> .kolla_configs
  else 
    RACK=$RACK;
fi

if  [ -z "$KOLLA_VERSION" ]; 
then
  echo "What version of Kolla?"
  options=("4.0.0" "4.0.2")
  select kolla in "${options[@]}"
  do
    case $kolla in
        "4.0.0" ) 
           echo "KOLLA_VERSION=4.0.0" >> .kolla_configs
           KOLLA_VERSION=4.0.0;break;;
        "4.0.2" ) 
           echo "KOLLA_VERSION=4.0.2" >> .kolla_configs
           KOLLA_VERSION=4.0.2;break;;
        * ) echo "Invalid option";;
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
  cp globals.yml /etc/kolla/globals.yml
  rm globals.yml
}

function create_docker_repo_and_images () {
  echo ""
  echo "<create_docker_repo_and_images>"
  echo ""
  echo "Creating a local docker repo (registry2)...."
  echo "Building ubuntu source kolla images..."
  echo "   this is going to take a while..."
  echo ""
  echo ""
  echo ""
  docker run -d \
      --name registry \
      --restart=always \
      -p 4000:5000 \
      -v registry:/var/lib/registry \
      registry:2
  kolla-build -t source -b ubuntu --registry 127.0.0.1:4000 --push
}

function quick_docker_repo_and_images () {
  echo ""
  echo "This is going to download the tarball from openstack kolla gates"
  echo "    The new images will be added to the registry and can be explored by going to:"
  echo ""
  echo "    cd /opt/kolla_registry"
  echo ""
  wget http://tarballs.openstack.org/kolla/images/ubuntu-source-registry-ocata.tar.gz
  mkdir /opt/kolla_registry
  sudo tar xzf ubuntu-source-registry-ocata.tar.gz -C /opt/kolla_registry
  docker run -d -p 4000:5000 --restart=always -v /opt/kolla_registry/:/var/lib/registry --name registry registry:2
  #sed -i "/#?docker_namespace: .*/docker_namespace: \"lokolla\"/g"
}


function delete_docker_repo_and_images () {
  echo ""
  echo "<delete_docker_repo_and_images>"
  echo ""
  echo "DELETING the local docker repo and images..."
  echo ""
  echo ""
  echo ""
  sleep $SLEEP
  docker kill `docker ps -a | awk '{print $1}'`
  docker rmi -f `docker images | grep none | awk '{print $3}'`
  docker rmi -f `docker images | grep kolla | awk '{print $3}'`
  docker rmi `docker images | grep ubuntu | awk '{print $3}'`
  docker stop `docker ps -a | grep registry | awk '{print $1}'`
  docker rmi -f `docker images | grep registry | awk '{print $3}'`
  rm -R /opt/kolla_registry
  
}

function Reboot () {
  ansible-playbook -i $INVENTORY_FILE  main.yml --tags "Reboot"
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
  pip install -U ansible==2.3.0.0
  pip uninstall -U Jinja2 
  pip install -U Jinja2==2.8
  #pip install -U git+https://github.com/openstack/kolla-ansible.git@stable/ocata
  pip install kolla-ansible==$KOLLA_VERSION
  curl -sSL https://get.docker.io | bash
  pip install kolla==$KOLLA_VERSION
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
  echo " Sets up ceph, kolla bootstrap, and genpwd"
  echo ""
  #ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "oneTime" -u ubuntu --extra-vars='{"CIDR": "0.0.0.0"}'
  ansible -i $INVENTORY_FILE -m apt -a "name=python state=present" --become all -u ubuntu -e ansible_python_interpreter=/usr/bin/python3
  ansible-playbook -i $INVENTORY_FILE  main.yml --tags "oneTime" -u ubuntu --extra-vars='{"CIDR": "0.0.0.0"}'
  ansible-playbook -i $INVENTORY_FILE  main.yml --tags "generate_public_interfaces" -u ubuntu
  #ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "generate_public_interfaces" -u ubuntu
  ansible -i $INVENTORY_FILE -m shell -a "parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP 1 -1" storage 
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vasrs='{"CIDR":"0.0.0.0"}'
  #ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "ceph" -u ubuntu --extra-vars='{"CIDR": "0.0.0.0"}'
  kolla-genpwd
  kolla-ansible -i $INVENTORY_FILE bootstrap-servers
  kolla-ansible certificates
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "destroy_public_interfaces" --extra-vars='{"CIDR":"0.0.0.0"}'
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vars='{"CIDR":"0.0.0.0"}'
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
  ansible-playbook -i "$INVENTORY_FILE" kolla_bridge.yml --tags "kill_VMs" --extra-vars='{"CIDR":"0.0.0.0"}'
  kolla-ansible -i "$INVENTORY_FILE" destroy --yes-i-really-really-mean-it
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "ceph" --extra-vars='{"CIDR":"0.0.0.0"}'
#  ansible -i $INVENTORY_FILE -m shell -a "parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP 1 -1" storage
#  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vars='{"CIDR":"0.0.0.0"}'
  echo "Do you with to delete ALL containers on hosts too?"
  select yn in "Yes" "No"; do
    case $yn in
        Yes ) ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "nuke_it" --extra-vasrs='{"CIDR":"0.0.0.0"}'; break;;
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
  echo -e "$(date) \t -- \t Kolla $KOLLA will be deployed on Rack $RACK" >> deploy_history.log
  kolla-ansible deploy -i "$INVENTORY_FILE" -vv
  sleep "$SLEEP"
}

function post_deploy () {
  kolla-ansible post-deploy
  cat /etc/kolla/admin-openrc.sh | grep OS_PASSWORD
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
    echo "  create_docker_repo_and_images"
    echo "    creates the docker repo and builds images"
    echo ""
    echo "  one_time"
    echo "    Installs necessary components"
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
    echo "  delete_docker_repo_and_images"
    echo "    deletes all docker images"
    echo ""
    echo "  deploy_all"
    echo "    precheck"
    echo "    deploy"
    echo "    post_deploy"
    echo ""
    echo ""
    echo ""
    echo -e "\033[33;7mCURRENTLY SET TO DEPLOY KOLLA $KOLLA_VERSION TO RACK $RACK ### \033[0m"
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
        "delete_docker_repo_and_images")
            delete_docker_repo_and_images
            ;;
        "create_docker_repo_and_images")
            create_docker_repo_and_images
            ;;
        "Reboot")
            Reboot
            ;;
        "quick_docker_repo_and_images")
            quick_docker_repo_and_images
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
