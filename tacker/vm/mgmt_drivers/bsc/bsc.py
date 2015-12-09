# Copyright 2015 Brocade Communication Systems, Inc.
# All Rights Reserved.
#
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.


import json
import time
import yaml

from oslo_config import cfg

from pybvc.controller.controller import Controller
from pybvc.netconfdev.vrouter.vrouter5600 import VRouter5600
from pybvc.common.status import STATUS
from pybvc.common.utils import load_dict_from_file

from tacker.common import exceptions
from tacker.common import log
from tacker.openstack.common import jsonutils
from tacker.openstack.common import log as logging
from tacker.vm.mgmt_drivers import abstract_driver
from tacker.vm.mgmt_drivers import constants as mgmt_constants


LOG = logging.getLogger(__name__)

class BscMgmtDriverException(exceptions.TackerException):
    message = _("%(msg)s")

class DeviceMgmtBsc(abstract_driver.DeviceMGMTAbstractDriver):

    def get_type(self):
        return 'bsc'

    def get_name(self):
        return 'bsc'

    def get_description(self):
        return 'Tacker DeviceMgmt Bsc Driver'

    def mgmt_url(self, plugin, context, device):
        LOG.debug(_('mgmt_url %s'), device)
        return device.get('mgmt_url', '')

    @log.log
    def _get_controller(self, controller_dict):
        try:
            ctrlIpAddr = controller_dict['address']
            ctrlPortNum = controller_dict['port']
            ctrlUname = controller_dict['username']
            ctrlPswd = controller_dict['password']
            ctrl = Controller(ctrlIpAddr, ctrlPortNum, ctrlUname, ctrlPswd)
        except:
            message = "Failed to get controller device attributes"
            LOG.debug("%s" % message)
            raise BscMgmtDriverException(msg=message)
        return ctrl

    @log.log
    def _get_vrouter(self, ctrl, node_dict, mgmt_ip_address):
        try:
            nodeName = node_dict['name']+"-"+mgmt_ip_address
            nodeIpAddr = mgmt_ip_address
            nodePortNum = node_dict['port']
            nodeUname = node_dict['username']
            nodePswd = node_dict['password']
            vrouter = VRouter5600(ctrl, nodeName, nodeIpAddr,
                              nodePortNum, nodeUname, nodePswd)
        except:
            message = "Failed to get node device attributes"
            LOG.debug("%s" % message)
            raise BscMgmtDriverException(msg=message)
        return vrouter

    @log.log
    def _mount_node(self, ctrl, node):
        node_configured = False
        result = ctrl.check_node_config_status(node.name)
        status = result.get_status()
        if(status.eq(STATUS.NODE_CONFIGURED)):
            node_configured = True
            LOG.debug("'%s' is configured on the Controller" % node.name)
        elif(status.eq(STATUS.DATA_NOT_FOUND)):
            node_configured = False
        else:
            message = "Failed to get configuration status for %s " % node.name
            LOG.debug("%s " % message)
            raise BscMgmtDriverException(msg=message)

        if node_configured is False:
            result = ctrl.add_netconf_node(node)
            status = result.get_status()
            if(status.eq(STATUS.OK)):
                LOG.debug("'%s' added to the Controller" % node.name)
            else:
                message = "Error : %s" % status.detailed()
                LOG.debug(message)
                raise BscMgmtDriverException(msg=message)

        time.sleep(60)
        result = ctrl.check_node_conn_status(node.name)
        status = result.get_status()
        if(status.eq(STATUS.NODE_CONNECTED)):
            LOG.debug("'%s' is connected to the Controller" % node.name)
        else:
            message = "Error : %s" % status.brief().lower()
            LOG.debug(message)
            raise BscMgmtDriverException(msg=message)

        LOG.debug("Get list of all YANG models supported by the '%s'"
                  % node.name)
        # TODO: Figure out if and why the below 6 lines of code are needed
        result = node.get_schemas()
        status = result.get_status()
        if(status.eq(STATUS.OK)):
            slist = result.get_data()
            LOG.debug(json.dumps(slist, default=lambda o: o.__dict__,
                             sort_keys=True, indent=4))
        else:
            message = ("Error: %s" % status.brief().lower())
            LOG.debug(message)
            raise BscMgmtDriverException(msg=message)

    @log.log
    def _umount_node(self, ctrl, node):
        LOG.debug(" Remove '%s' NETCONF node from the Controller" % node.name)
        time.sleep(3)
        result = ctrl.delete_netconf_node(node)
        status = result.get_status()
        if(status.eq(STATUS.OK)):
            LOG.debug("'%s' NETCONF node was successfully removed "
                   "from the Controller" % node.name)
        else:
            message = ("Error: %s" % status.brief())
            LOG.debug(message)
            raise BscMgmtDriverException(msg=message)

    @log.log
    def _execute_bsc_action(self, ctrl, node, action):
        if action == mgmt_constants.ACTION_UPDATE_DEVICE:
            self._mount_node(ctrl, node)
        elif action == mgmt_constants.ACTION_DELETE_DEVICE:
            self._umount_node(ctrl, node)

    @log.log
    def mgmt_call(self, plugin, context, device, kwargs):
        ACTION = kwargs[mgmt_constants.KEY_ACTION]
        if ACTION != mgmt_constants.ACTION_UPDATE_DEVICE and ACTION != \
                mgmt_constants.ACTION_DELETE_DEVICE:
            return
        dev_attrs = device.get('attributes', {})
        mgmt_url = jsonutils.loads(device.get('mgmt_url', '{}'))
        if not mgmt_url:
            return

        config = dev_attrs.get('config', '')
        if not config:
            return
        config_yaml = yaml.load(config) or {}
        if not config_yaml:
            return

        vdus_config_dict = config_yaml.get('vdus', {})
        node_dict = config_yaml.get('node', {})
        controller_dict = config_yaml.get('controller', {})

        if not (vdus_config_dict and node_dict and controller_dict):
            message = ("Error: One or all of VDUs, node or controller "
                       "information missing")
            LOG.debug(msg=message)
            raise BscMgmtDriverException(msg=message)
        # TODO: Add code to check if all the required keys are present

        ctrl = self._get_controller(controller_dict)
        for vdu, vdu_dict in vdus_config_dict.items():
            mgmt_ip_address = mgmt_url.get(vdu, '')
            LOG.debug("mgmt_ip_address %s", mgmt_ip_address)
            if not mgmt_ip_address:
                LOG.warn(_('tried to configure unknown mgmt address %s'),
                         vdu)
                continue
            node = self._get_vrouter(ctrl,node_dict,mgmt_ip_address)
            self._execute_bsc_action(ctrl, node, ACTION)

    def mgmt_service_address(self, plugin, context,
                             device, service_instance):
        LOG.debug(_('mgmt_service_address %(device)s %(service_instance)s'),
                  {'device': device, 'service_instance': service_instance})
        return 'noop-mgmt-service-address'

    def mgmt_service_call(self, plugin, context, device,
                          service_instance, kwargs):
        LOG.debug(_('mgmt_service_call %(device)s %(service_instance)s'),
                  {'device': device, 'service_instance': service_instance})
