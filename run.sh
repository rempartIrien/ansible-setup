#!/bin/zsh

# Before running this script, connect with SSH just to get the SSH key fingerprint.
# Otherwise, sshpass won't connect.
#
# Be sure to have all your domains set properly in your DNS provider manager.
# Otherwise, Let's Encrypt will raise errors to Caddy.
#
# After running the script, put the generated SSH public key in your Git provider
# to use webhooks.
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
ansible-playbook -i ./inventory.yml ./main.yml
