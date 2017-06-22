#!/bin/bash
SLEEP=5
TMP_INVENTORY_FILE="tmp6"
INVENTORY_FILE="multinode6"
# Verify:
#  - SSH access with root user is possible
#  - /etc/hosts file has all hostnames in it

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
  #pip install -U git+https://github.com/openstack/kolla-ansible.git@stable/ocata
  pip install kolla-ansible==4.0.2
  curl -sSL https://get.docker.io | bash
  pip install kolla==4.0.2
  #pip install -U git+https://github.com/openstack/kolla.git@stable/ocata
  cp -r /usr/local/share/kolla-ansible/etc_examples/kolla /etc/kolla/
}

function settings () {
  echo ""
  echo "<settings>"
  echo ""
  echo " Copying default settings and moving YOUR global file to /etc/kolla"
  echo ""
  cp -r /usr/local/share/kolla-ansible/etc_examples/kolla /etc/kolla/
#cp /usr/local/share/kolla-ansible/ansible/inventory/* .
  cp globals.yml /etc/kolla/globals.yml
}

function bootstrap () {
  echo ""
  echo "<bootstrap>"
  echo ""
  echo " Sets up ceph, kolla bootstrap, and genpwd"
  echo ""
  ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "oneTime" -u ubuntu --extra-vars='{"CIDR": "0.0.0.0"}'
  ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "generate_public_interfaces" -u ubuntu
  ansible -i $INVENTORY_FILE -m shell -a "parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP 1 -1" storage 
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vasrs='{"CIDR":"0.0.0.0"}'
  #ansible-playbook -i $TMP_INVENTORY_FILE  main.yml --tags "ceph" -u ubuntu --extra-vars='{"CIDR": "0.0.0.0"}'
  kolla-genpwd
  kolla-ansible -i $INVENTORY_FILE bootstrap-servers
  kolla-ansible certificates
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "destroy_public_interfaces" --extra-vasrs='{"CIDR":"0.0.0.0"}'
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vasrs='{"CIDR":"0.0.0.0"}'
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
  ansible-playbook -i "$TMP_INVENTORY_FILE" kolla_bridge.yml --tags "kill_VMs" --extra-vars='{"CIDR":"0.0.0.0"}'
  kolla-ansible -i "$INVENTORY_FILE" destroy --yes-i-really-really-mean-it
  #ansible -i $INVENTORY_FILE -m shell -a "parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP 1 -1" storage
  ansible -i $INVENTORY_FILE -m shell -a "dd if=/dev/zero of=/dev/sdb count=1000 bs=1M" storage
  ansible -i $INVENTORY_FILE -m shell -a "parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP 1 -1" storage
  ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "Reboot" --extra-vars='{"CIDR":"0.0.0.0"}'
  #ansible-playbook -i "$INVENTORY_FILE"  main.yml --tags "ceph" --extra-vars='{"CIDR":"0.0.0.0"}'
  echo "Do you with to delete ALL containers on hosts too?"
  select yn in "Yes" "No"; do
    case $yn in
        Yes ) ansible-playbook -i "$INVENTORY_FILE" main.yml --tags "nuke_it" --extra-vasrs='{"CIDR":"0.0.0.0"}'; break;;
        No ) exit;;
    esac
  done
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
  kolla-ansible deploy -i "$INVENTORY_FILE" -vv
  sleep "$SLEEP"
}

function post_deploy () {
  kolla-ansible post-deploy
  cat /etc/kolla/admin-openrc.sh | grep OS_PASSWORD
  ./setup_networking.sh deploy
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
        esac
    fi
}

main "$1"
