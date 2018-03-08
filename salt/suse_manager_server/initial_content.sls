{% if grains['for_development_only'] %}

include:
  - suse_manager_server.rhn

create_first_user:
  http.wait_for_successful_query:
    - method: POST
    - name: https://localhost/rhn/newlogin/CreateFirstUser.do
    - match: Discover a new way of managing your servers
    - data: "submitted=true&\
             orgName=SUSE&\
             login=admin&\
             desiredpassword=admin&\
             desiredpasswordConfirm=admin&\
             email=galaxy-noise%40suse.de&\
             firstNames=Administrator&\
             lastName=McAdmin"
    - verify_ssl: False
    - unless: spacecmd -u admin -p admin user_list | grep -x admin
    - require:
      - sls: suse_manager_server.rhn

mgr_sync_configuration_file:
  file.managed:
    - name: /root/.mgr-sync
    - replace: false
    - require:
      - http: create_first_user

mgr_sync_automatic_authentication:
  file.replace:
    - name: /root/.mgr-sync
    - pattern: mgrsync.user =.*\nmgrsync.password =.*\n
    - repl: |
        mgrsync.user = admin
        mgrsync.password = admin
    - append_if_not_found: true
    - require:
      - file: mgr_sync_configuration_file

{% if grains.get('channels') %}
wait_for_mgr_sync:
  cmd.script:
    - name: salt://suse_manager_server/wait_for_mgr_sync.py
    - use_vt: True
    - require:
      - http: create_first_user

scc_data_refresh:
  cmd.run:
    - name: mgr-sync refresh
    - use_vt: True
    - unless: spacecmd -u admin -p admin --quiet api sync.content.listProducts | grep name
    - require:
      - cmd: wait_for_mgr_sync
{% endif %}

{% if grains.get('channels') %}
add_channels:
  cmd.run:
    - name: mgr-sync add channels {{ ' '.join(grains['channels']) }}
    - require:
      - cmd: scc_data_refresh

{% for channel in grains.get('channels') %}
reposync_{{ channel }}:
  cmd.script:
    - name: salt://suse_manager_server/wait_for_reposync.py
    - args: "admin admin localhost {{ channel }}"
    - use_vt: True
    - require:
      - cmd: add_channels
{% endfor %}
{% endif %}

create_empty_channel:
  cmd.run:
    - name: spacecmd -u admin -p admin -- softwarechannel_create --name testchannel -l testchannel -a x86_64
    - unless: spacecmd -u admin -p admin softwarechannel_list | grep -x testchannel
    - require:
      - http: create_first_user

create_empty_activation_key:
  cmd.run:
    - name: spacecmd -u admin -p admin -- activationkey_create -n DEFAULT -b testchannel
    - unless: spacecmd -u admin -p admin activationkey_list | grep -x 1-DEFAULT
    - require:
      - cmd: create_empty_channel

create_empty_bootstrap_script:
  cmd.run:
    - name: rhn-bootstrap --activation-keys=1-DEFAULT --no-up2date --hostname {{ grains['hostname'] }}.{{ grains['domain'] }} {{ '--traditional' if '3.0' not in grains['version'] else '' }}
    - creates: /srv/www/htdocs/pub/bootstrap/bootstrap.sh
    - require:
      - cmd: create_empty_activation_key

create_empty_bootstrap_script_md5:
  cmd.run:
    - name: sha512sum /srv/www/htdocs/pub/bootstrap/bootstrap.sh > /srv/www/htdocs/pub/bootstrap/bootstrap.sh.sha512
    - creates: /srv/www/htdocs/pub/bootstrap/bootstrap.sh.sha512
    - require:
      - cmd: create_empty_bootstrap_script

private_ssl_key:
  file.copy:
    - name: /srv/www/htdocs/pub/RHN-ORG-PRIVATE-SSL-KEY
    - source: /root/ssl-build/RHN-ORG-PRIVATE-SSL-KEY
    - mode: 644
    - require:
      - sls: suse_manager_server.rhn

private_ssl_key_checksum:
  cmd.run:
    - name: sha512sum /srv/www/htdocs/pub/RHN-ORG-PRIVATE-SSL-KEY > /srv/www/htdocs/pub/RHN-ORG-PRIVATE-SSL-KEY.sha512
    - creates: /srv/www/htdocs/pub/RHN-ORG-PRIVATE-SSL-KEY.sha512
    - require:
      - file: private_ssl_key

ca_configuration:
  file.copy:
    - name: /srv/www/htdocs/pub/rhn-ca-openssl.cnf
    - source: /root/ssl-build/rhn-ca-openssl.cnf
    - mode: 644
    - require:
      - sls: suse_manager_server.rhn

ca_configuration_checksum:
  cmd.run:
    - name: sha512sum /srv/www/htdocs/pub/rhn-ca-openssl.cnf > /srv/www/htdocs/pub/rhn-ca-openssl.cnf.sha512
    - creates: /srv/www/htdocs/pub/rhn-ca-openssl.cnf.sha512
    - require:
      - file: ca_configuration

{% endif %}
