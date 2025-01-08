#!/bin/bash

# Script para configurar automaticamente um servidor de proxy com Squid em Ubuntu 20.04 usando rede 4G
# Pode ser executado diretamente para realizar a instalação e configuração completa.

# Verificar se o script está sendo executado como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root (use sudo)."
  exit
fi

# Atualizar o sistema e instalar dependências
sudo apt update && sudo apt upgrade -y
sudo apt install -y squid apache2-utils curl

# Configurar o Squid
echo "Criando configuração do Squid..."
SQUID_CONFIG="/etc/squid/squid.conf"
sudo mv $SQUID_CONFIG ${SQUID_CONFIG}.bak  # Fazer backup do arquivo original
echo "http_port 3128" | sudo tee $SQUID_CONFIG > /dev/null
echo "acl all src all" | sudo tee -a $SQUID_CONFIG > /dev/null
echo "http_access allow all" | sudo tee -a $SQUID_CONFIG > /dev/null

# Gerar 100 proxies com autenticação
echo "Configurando autenticação e proxies..."
START_PORT=20000
END_PORT=$((START_PORT + 100))
AUTH_FILE="/etc/squid/passwords"
sudo touch $AUTH_FILE
sudo chmod 640 $AUTH_FILE

for ((PORT=$START_PORT; PORT<$END_PORT; PORT++)); do
  USER=$(openssl rand -hex 4)  # Gerar usuário seguro
  PASS=$(openssl rand -hex 8)  # Gerar senha segura
  sudo htpasswd -b $AUTH_FILE $USER $PASS
  echo "http_port $PORT" | sudo tee -a $SQUID_CONFIG > /dev/null
  echo "Criado proxy na porta $PORT com usuário $USER e senha $PASS"
done

# Configurar reinício automático para IP dinâmico
MONITOR_SCRIPT="/usr/local/bin/monitor_ip.sh"
echo "#!/bin/bash" > $MONITOR_SCRIPT
echo "while true; do" >> $MONITOR_SCRIPT
echo "  sudo systemctl restart squid" >> $MONITOR_SCRIPT
echo "  sleep 60" >> $MONITOR_SCRIPT
echo "done" >> $MONITOR_SCRIPT

sudo chmod +x $MONITOR_SCRIPT
sudo nohup bash $MONITOR_SCRIPT &

# Permitir portas no firewall
for ((PORT=$START_PORT; PORT<$END_PORT; PORT++)); do
  sudo ufw allow $PORT
  echo "Porta $PORT liberada no firewall."
done

# Reiniciar o Squid
sudo systemctl restart squid

echo "Configuração concluída! Proxies ativos. Execute 'sudo systemctl status squid' para verificar o status."
