#!/bin/bash

# Verify:
#  - SSH access with root user is possible
#  - /etc/hosts file has all hostnames in it

function create_docker_repo_and_images () {
  echo ""
  echo ""
  echo ""
  echo "Creating a local docker repo..."
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
  echo ""
  echo ""
  echo "DELETING the local docker repo and images..."
  echo ""
  echo ""
  echo ""
  sleep 5
  docker rmi -f `docker images | grep kolla | awk '{print $3}'`
  docker rmi `docker images | grep ubuntu | awk '{print $3}'`
  docker stop `docker ps -a | grep registry | awk '{print $1}'`
  docker rmi -f `docker images | grep registry | awk 'print $3}'`
}


function one_time () {
  echo ""
  echo " Installing all pre-req's to get Kolla deployment up and running"
  echo "    Also sets up interfaces defined in tmp"
  apt update
  apt install -y python-pip
  pip install -U pip
  apt install -y python-dev libffi-dev gcc libssl-dev
  pip install -U ansible
  pip install -U kolla-ansible
  curl -sSL https://get.docker.io | bash
  pip install -U kolla
  cp -r /usr/local/share/kolla-ansible/etc_examples/kolla /etc/kolla/
}

function settings () {
  echo ""
  echo " Copying default settings and moving YOUR global file to /etc/kolla"
  echo ""
  cp -r /usr/local/share/kolla-ansible/etc_examples/kolla /etc/kolla/
#cp /usr/local/share/kolla-ansible/ansible/inventory/* .
  cp globals.yml /etc/kolla/globals.yml
}

function bootstrap () {
  echo ""
  echo " Sets up ceph, kolla bootstrap, and genpwd"
  echo ""
  ansible-playbook -i tmp  kolla_bridge.yml --tags "oneTime,interface"
  ansible-playbook -i tmp  kolla_bridge.yml --tags "ceph"
#  ansible-playbook -i tmp  kolla_bridge.yml --tags reboot
  kolla-ansible -i multinode bootstrap-servers
  kolla-genpwd
}

function destroy () {
  ansible-playbook -i tmp kolla_bridge.yml --tags "kill_VMs"
  kolla-ansible -i multinode destroy --yes-i-really-really-mean-it
  ansible-playbook -i tmp  kolla_bridge.yml --tags "ceph"
  while true; do
    read -p "Do you with to delete ALL containers on hosts too?" yn
    case $yn in
      [Yy]* ) ansible-playbook -i tmp kolla_bridge.yml --tags "delete_images"; break;;
      [Nn]* ) exit;;
      * ) echo "Please answer yes or no.";;
    esac
  done
}



function prechecks () {
  echo ""
  echo " Kolla prechecks and pull images local"
  echo ""
  kolla-ansible prechecks -i multinode
  sleep 10
  kolla-ansible pull -i multinode
  sleep 5
}

function deploy () {
  echo ""
  echo " Kolla deploy"
  echo ""
  kolla-ansible deploy -i multinode -vv
  sleep 5
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
    echo "  "
    echo "  one_time"
    echo "    Installs necessary components"
    echo "    "
    echo "  settings"
    echo "    Moves local global.yml to /etc/kolla/global.yml"
    echo "    "
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
    echo ""
    echo "  post_deploy"
    echo "    runs the post-deploy and cat's out admin password"
    echo "  "
    echo "  destroy"
    echo "    destroys the evironment and wipes ceph"
    echo "  "
    echo "  delete_docker_repo_and_images"
    echo "    deletes all docker images"
    echo "  "
    echo "  create_docker_repo_and_images"
    echo "    creates the docker repo and builds images"
    echo "  "
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
        esac
    fi
}

main "$1"
