docker exec -i Zabbix_DB mysql -uzabbix -pzabbixpass zabbix < ./zabbix-init/schema.sql
docker exec -i Zabbix_DB mysql -uzabbix -pzabbixpass zabbix < ./zabbix-init/data.sql

# User : Admin 
# Password : zabbix