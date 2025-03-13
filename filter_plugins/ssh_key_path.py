#!/usr/bin/python

class FilterModule(object):
    def filters(self):
        return {
            'ssh_key_path': self.ssh_key_path
        }

    def ssh_key_path(self, key_name, user):
        return f"/home/{user}/.ssh/id_rsa_{key_name}"
