#!/bin/bash

# Verify:
#  - SSH access with root user is possible
#  - /etc/hosts file has all hostnames in it

function local_docker_repo () {
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


function one_time () {
  echo ""
  echo " Installing all pre-req's to get Kolla up and running"
  echo ""
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
  ansible-playbook -i tmp  kolla_bridge.yml
  kolla-ansible -i multinode bootstrap-servers
  kolla-genpwd
}

function prechecks () {
  kolla-ansible prechecks -i multinode
  kolla-ansible pull -i multinode
}

function deploy () {
  kolla-ansible deploy -i multinode
}

function post_deploy () {
  kolla-ansible post-deploy
  cat /etc/kolla/admin-openrc.sh | grep OS_PASSWORD
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
        esac
    fi
}

main "$1"
