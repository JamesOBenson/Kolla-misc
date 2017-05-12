
Misc. scripts that help with kolla deployments.


##kolla_bridge.yml
execute: ansible-playbook -i multinode kolla_bridge.yml

This will go into your hosts file of kolla:
   
   - for controllers:
    - Assign previous IP address given for eno2 to the bridge
    - create veth0
    - create veth1
   - for non-controllers:
    - Create an anon. bridge (no IP)
    - create veth0
    - create veth0
    - create veth1
