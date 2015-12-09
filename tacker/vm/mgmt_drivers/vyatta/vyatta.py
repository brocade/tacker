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


import paramiko
import time
import yaml

from oslo_config import cfg

from tacker.common import exceptions
from tacker.common import log
from tacker.openstack.common import jsonutils
from tacker.openstack.common import log as logging
from tacker.vm.mgmt_drivers import abstract_driver
from tacker.vm.mgmt_drivers import constants as mgmt_constants
from tacker.vm.mgmt_drivers.vyatta import ssh_connector

LOG = logging.getLogger(__name__)
OPTS = [
    cfg.StrOpt('user', default='vyatta', help=_('user name to login vyatta')),
    cfg.StrOpt('password', default='vyatta', help=_('password to login vyatta')),
]
cfg.CONF.register_opts(OPTS, 'vyatta')

PREFIX = "\nconfigure\n"
SUFFIX = "\ncommit\nsave\n"


class ConfigurationFailed(exceptions.TackerException):
    message = _("Configuration failed. "
                "Refer documentation for supported configuration commands."
                "Error details %(msg)s")

class ParamikoSSHException(exceptions.TackerException):
    message = _("%(msg)s")

class DeviceMgmtVyatta(abstract_driver.DeviceMGMTAbstractDriver):

    def get_type(self):
        return 'vyatta'

    def get_name(self):
        return 'vyatta'

    def get_description(self):
        return 'Tacker DeviceMgmt Vyatta Driver'

    def mgmt_url(self, plugin, context, device):
        LOG.debug(_('mgmt_url %s'), device)
        return device.get('mgmt_url', '')

    @log.log
    def _execute_vyatta_cli(self, mgmt_ip_address, config):
        user = cfg.CONF.vyatta.user
        password = cfg.CONF.vyatta.password
        LOG.debug("vyatta cli command - %s" % config)

        try:
            sshobj = paramiko.SSHClient()
            sshobj.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            sshobj.connect(mgmt_ip_address,username=user,password=password)
            channel = sshobj.invoke_shell()
            channel.send(PREFIX)
            channel.send("\n".join(config))
            channel.send(SUFFIX)
            time.sleep(3)
            stdout_buff = channel.recv(10000)
            LOG.debug(_("Vyatta Config response - %s") % stdout_buff)
            if 'failed' in stdout_buff:
                raise ConfigurationFailed(msg=stdout_buff)
        except paramiko.SSHException as e:
            LOG.debug("Paramiko SSHException %s"
                      % e.message)
            raise ParamikoSSHException(msg=e.message)
        finally:
            sshobj.close()

    @log.log
    def mgmt_call(self, plugin, context, device, kwargs):
        if (kwargs[mgmt_constants.KEY_ACTION] !=
            mgmt_constants.ACTION_UPDATE_DEVICE):
            return
        dev_attrs = device.get('attributes', {})

        mgmt_url = jsonutils.loads(device.get('mgmt_url', '{}'))
        if not mgmt_url:
            return

        vdus_config = dev_attrs.get('config', '')
        config_yaml = yaml.load(vdus_config)
        if not config_yaml:
            return
        vdus_config_dict = config_yaml.get('vdus', {})
        time.sleep(120)
        for vdu, vdu_dict in vdus_config_dict.items():
            config = vdu_dict.get('config', [])
            if config:
                mgmt_ip_address = mgmt_url.get(vdu, '')
                LOG.debug("mgmt_ip_address %s", mgmt_ip_address)
                if not mgmt_ip_address:
                    LOG.warn(_('tried to configure unknown mgmt address %s'),
                             vdu)
                    continue
                self._execute_vyatta_cli(mgmt_ip_address, config)

    def mgmt_service_address(self, plugin, context,
                             device, service_instance):
        LOG.debug(_('mgmt_service_address %(device)s %(service_instance)s'),
                  {'device': device, 'service_instance': service_instance})
        return 'noop-mgmt-service-address'

    def mgmt_service_call(self, plugin, context, device,
                          service_instance, kwargs):
        LOG.debug(_('mgmt_service_call %(device)s %(service_instance)s'),
                  {'device': device, 'service_instance': service_instance})
