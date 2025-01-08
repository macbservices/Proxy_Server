#!/bin/bash

# Verifica se o script está sendo executado como root
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script deve ser executado como root."
    exit 1
fi

# Atualiza o sistema e instala o Squid
apt update && apt upgrade -y
apt install -y squid apache2-utils

# Backup do arquivo de configuração original
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# Define o IP público e o IP interno
target_ip_public="205.164.75.239"
target_ip_internal="100.102.90.11"

# Arquivo para salvar os proxies
proxy_list_file="/etc/squid/proxy_list.txt"
> "$proxy_list_file" # Limpa o arquivo caso exista

# Gerador de senhas seguras
function generate_password() {
  openssl rand -hex 8
}

# Cria um arquivo de senhas para autenticação
auth_file="/etc/squid/passwords"
htpasswd -c -b "$auth_file" user_placeholder pass_placeholder # Cria o arquivo inicial

# Remove o usuário placeholder
sed -i '/user_placeholder/d' "$auth_file"

# Configurações básicas do Squid
cat <<EOL > /etc/squid/squid.conf
http_port 3128
acl localnet src $target_ip_internal/32
acl Safe_ports port 80		# http
acl Safe_ports port 443		# https
acl Safe_ports port 3128	# proxy default
acl CONNECT method CONNECT

# Configuração de autenticação
auth_param basic program /usr/lib/squid/basic_ncsa_auth $auth_file
auth_param basic realm Proxy
acl authenticated proxy_auth REQUIRED

# Permitir apenas conexões autenticadas
http_access allow authenticated
http_access deny all

# Configurações de log
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log

# Otimizações de performance
cache_mem 64 MB
maximum_object_size_in_memory 512 KB
maximum_object_size 1024 MB
cache_dir ufs /var/spool/squid 100 16 256

# Configuração personalizada de proxy
visible_hostname proxy-server
EOL

# Configuração de múltiplos proxies
for i in $(seq 1 10); do
  port=$((20000 + i))
  username="user_$i"
  password="$(generate_password)"

  # Adiciona o usuário ao arquivo de senhas
  htpasswd -b "$auth_file" "$username" "$password"

  # Adiciona a configuração do proxy ao Squid
  echo "http_port $target_ip_public:$port" >> /etc/squid/squid.conf

  # Salva no arquivo de lista de proxies
  echo "$target_ip_public:$port:$username:$password" >> "$proxy_list_file"
done

# Reinicia o serviço Squid
systemctl restart squid
systemctl enable squid

# Exibe as informações
echo "\nSquid instalado e configurado com sucesso!"
echo "Os seguintes proxies estão disponíveis (salvos em $proxy_list_file):"
cat "$proxy_list_file"
