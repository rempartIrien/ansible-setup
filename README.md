# ansible-setup

See https://github.com/madalinpopa/ubuntu-server-automation

## What to do before

- Configure A and AAAA records in DNS provider control panel
- Create an access token in GitHub and put it in secrets files to create deploy keys
- Connect through SSH just once so that your computer knows the remote host
- Create `inventory.yml` file such as
  ```yml
  ---
  all:
    hosts:
      vps:
        ansible_host: # host IP
        ansible_user: # initial SSH user, usually `root`
        ansible_become_pass: # initial user password
        ansible_ssh_pass: # initial user SSH password
        username: # new user to create
        password: # new user password
  ```

## References

- Named pipe https://stackoverflow.com/a/63719458

## Workflow

## Backup postgreSQL

## Other stuff

- how to reconnect if I lose my Macbook
- Umami
- Woodpecker-ci
- Docker registry See https://www.digitalocean.com/community/tutorials/how-to-set-up-a-private-docker-registry-on-ubuntu-20-04 / Artifactory / Nexus / Harbor / Quay
- Back up image volume on Fly!!!
- remove Server: caddy header in error responses
