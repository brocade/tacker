#get variables defined in 01-openstack_vars
source ./02-export_var_cntrl
echo "MY_PUBLIC_IP=$MY_PUBLIC_IP"
LOGIN_USER=$(whoami)
echo "LOGIN_USER=$LOGIN_USER"
sleep 3

#Create Tacker database
mysql -u root -p$MYSQL_PWD -e "CREATE DATABASE $TACKER_DB;"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $TACKER_DB.* TO '$TACKER_DBUSER'@'localhost' IDENTIFIED BY '$TACKER_DBPASS';"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $TACKER_DB.* TO '$TACKER_DBUSER'@'%' IDENTIFIED BY '$TACKER_DBPASS';"

source $ADMIN_RC_FILE

openstack user create --domain default --password $TACKER_SVC_USER_PWD $TACKER_SVC_USER
openstack role add --project $SERVICE_TENANT --user $TACKER_SVC_USER $ADMIN_ROLE
openstack service create --name $TACKER_SVC_NAME --description "VNFM service" servicevm
openstack endpoint create --region $REGION servicevm public http://$MY_IP:8888/
openstack endpoint create --region $REGION servicevm internal http://$MY_IP:8888/
openstack endpoint create --region $REGION servicevm admin http://$MY_IP:8888/

cd ~/

git clone -b stable/liberty https://github.com/openstack/tacker.git
git clone -b stable/liberty https://github.com/openstack/python-tackerclient.git
git clone -b stable/liberty https://github.com/openstack/tacker-horizon.git

sudo apt-get -y install python-pip

#sudo pip install -r ~/tacker/requirements.txt
sudo pip install tosca-parser

cd ~/tacker
sudo python setup.py install

sudo mkdir /var/cache/tacker
sudo chown $LOGIN_USER:root /var/cache/tacker
sudo chmod 700 /var/cache/tacker

sudo sed -i "0,/service-password/s//$TACKER_SVC_USER_PWD/" /usr/local/etc/tacker/tacker.conf
sudo sed -i "0,/service-password/s//$NOVA_SVC_USER_PWD/" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|# connection = mysql://root:pass@127.0.0.1:3306/tacker|connection = mysql+pymysql://$TACKER_DBUSER:$TACKER_DBPASS@$MY_IP:3306/$TACKER_DB?charset=utf8|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|\[agent\]|\[agent\]\nroot_helper = sudo /usr/local/bin/tacker-rootwrap /usr/local/etc/tacker/rootwrap.conf|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|DEFAULT]|DEFAULT]\nauth_strategy = keystone|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|DEFAULT]|DEFAULT]\npolicy_file = \/usr\/local\/etc\/tacker\/policy.json|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|DEFAULT]|DEFAULT]\ndebug = True|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|DEFAULT]|DEFAULT]\nverbose = True|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|DEFAULT]|DEFAULT]\nuse_syslog = False|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|DEFAULT]|DEFAULT]\nstate_path = \/var\/lib\/tacker|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|auth_url = http://127.0.0.1:35357|auth_url = http://$MY_IP:35357|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|auth_uri = http://127.0.0.1:5000|auth_uri = http://$MY_IP:5000|g" /usr/local/etc/tacker/tacker.conf
sudo sed -i "s|identity_uri|#identity_uri|g" /usr/local/etc/tacker/tacker.conf

sudo mkdir /var/log/tacker

cd ~/python-tackerclient
sudo python setup.py install

cd ~/tacker-horizon
sudo python setup.py install
sudo cp openstack_dashboard_extensions/* /usr/share/openstack-dashboard/openstack_dashboard/enabled/

sudo service apache2 restart

sudo sed -i "s|flat_networks = public|flat_networks = public,mgmtphysnet0|g" /etc/neutron/plugins/ml2/ml2_conf.ini

cat << EOF | sudo tee -a /etc/neutron/plugins/ml2/ml2_conf.ini
[ovs]
bridge_mappings = public:br-ext,mgmtphysnet0:br-mgmt0
tunnel_bridge = br-tun
local_ip = $MY_IP
EOF

sudo ovs-vsctl add-br br-ext
sudo ovs-vsctl add-br br-mgmt0
sleep 1


sudo service neutron-server restart
sudo service neutron-dhcp-agent restart
sudo service neutron-metadata-agent restart
sudo service neutron-plugin-openvswitch-agent restart

source $ADMIN_RC_FILE
neutron net-create --provider:physical_network mgmtphysnet0 --shared --provider:network_type flat net_mgmt
sleep 1
neutron subnet-create net_mgmt 192.168.120.0/24
sleep 1
neutron net-create --shared net0
sleep 1
neutron subnet-create net0 10.10.0.0/24
sleep 1
neutron net-create --shared net1
sleep 1
neutron subnet-create net1 10.10.1.0/24
sleep 1

