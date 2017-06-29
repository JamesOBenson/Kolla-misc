Misc. scripts that help with kolla deployments.

execute:
./setup_kolla.sh
```
Setup openstack



Missing paramter. Please Enter one of the following options

Usage: ./setup_kolla.sh {Any of the options below}


  create_docker_repo_and_images
    creates the docker repo and builds images

  one_time
    Installs necessary components

  settings
    Moves local global.yml to /etc/kolla/global.yml

  Reboot
    Reboot all nodes

  bootstrap
    Fixes interfaces file for bridges
    bootstraps the servers
    generates passwords

  prechecks
    runs the prechecks
    pulls images based off of globals file

  deploy
    Destroy public interfaces besides controllers
    Deploy

  post_deploy
    runs the post-deploy and cat's out admin password

  destroy
    destroys the evironment and wipes ceph

  delete_docker_repo_and_images
    deletes all docker images

  deploy_all
    precheck
    deploy
    post_deploy
```


### Also be sure to update globals.template with correct settings as well.
