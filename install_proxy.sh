#!/bin/bash

# Script para configurar automaticamente um servidor de proxy com Squid em Ubuntu 20.04 usando rede 4G
# Inclui envio de lista de proxies por email a cada mudança de IP.
# Adiciona a solução para contornar bloqueio de portas, configurando o proxy na porta 443 (HTTPS)

# Verificar se o script está sendo executado como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root (use sudo)."
  exit
fi

# Perguntar ao usuário o Gmail e o destinatário do email
echo "Por favor, informe o Gmail para envio da lista de proxies:"
read GMAIL_USER

echo "Por favor, informe a senha do app (não a senha principal) para o Gmail:"
read -s GMAIL_PASS

echo "Por favor, informe o email do destinatário:"
read RECIPIENT

SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587

# Atualizar o sistema e instalar dependências
sudo apt update && sudo apt upgrade -y
sudo apt install -y squid apache2-utils curl msmtp msmtp-mta

# Configurar o msmtp (cliente de envio de email)
MSMTP_CONFIG="/etc/msmtprc"
echo "Criando configuração do msmtp..."
cat <<EOL | sudo tee $MSMTP_CONFIG > /dev/null
account default
host $SMTP_SERVER
port $SMTP_PORT
auth on
user $GMAIL_USER
password $GMAIL_PASS
tls on
tls_starttls on
logfile /var/log/msmtp.log
EOL
sudo chmod 600 $MSMTP_CONFIG
sudo chown root:root $MSMTP_CONFIG

# Configurar o Squid
echo "Criando configuração do Squid..."
SQUID_CONFIG="/etc/squid/squid.conf"
sudo mv $SQUID_CONFIG ${SQUID_CONFIG}.bak  # Fazer backup do arquivo original
echo "http_port 443" | sudo tee $SQUID_CONFIG > /dev/null  # Configurando o Squid para usar a porta 443
echo "acl all src all" | sudo tee -a $SQUID_CONFIG > /dev/null
echo "http_access allow all" | sudo tee -a $SQUID_CONFIG > /dev/null

# Gerar 100 proxies com autenticação
echo "Configurando autenticação e proxies..."
START_PORT=20000
END_PORT=$((START_PORT + 100))
AUTH_FILE="/etc/squid/passwords"
sudo touch $AUTH_FILE
sudo chmod 640 $AUTH_FILE
PROXY_LIST="/tmp/proxy_list.txt"
> $PROXY_LIST  # Limpar lista antiga

for ((PORT=$START_PORT; PORT<$END_PORT; PORT++)); do
  USER=$(openssl rand -hex 4)  # Gerar usuário seguro
  PASS=$(openssl rand -hex 8)  # Gerar senha segura
  sudo htpasswd -b $AUTH_FILE $USER $PASS
  IP=$(curl -s ifconfig.me)  # Capturar IP atual
  echo "$IP:$PORT:$USER:$PASS" >> $PROXY_LIST
  echo "http_port $PORT" | sudo tee -a $SQUID_CONFIG > /dev/null
  echo "Criado proxy na porta $PORT com usuário $USER e senha $PASS"
done

# Função para enviar a lista de proxies por email
enviar_email() {
  echo "Enviando lista de proxies por email..."
  
  # Verificar o conteúdo da lista de proxies antes de enviar
  if [ ! -s "$PROXY_LIST" ]; then
    echo "Erro: A lista de proxies está vazia!" >&2
    return 1
  fi
  
  # Enviar o email
  cat <<EOL | msmtp -t
To: $RECIPIENT
From: $GMAIL_USER
Subject: Lista de Proxies Atualizada

Segue a lista dos proxies atualizados:

$(cat $PROXY_LIST)
EOL

  # Verificar se o msmtp retornou erro
  if [ $? -ne 0 ]; then
    echo "Erro ao enviar o e-mail!" >&2
    return 1
  fi

  echo "Email enviado com sucesso!"
}

# Tentar enviar o email, se falhar, salvar a lista localmente
if ! enviar_email; then
  echo "Falha ao enviar e-mail. A lista de proxies foi salva localmente."
  PROXY_FILE_PATH="/var/log/proxy_list.txt"
  cp $PROXY_LIST $PROXY_FILE_PATH
  echo "Arquivo com a lista de proxies salva em: $PROXY_FILE_PATH"
fi

# Configurar reinício automático para IP dinâmico
MONITOR_SCRIPT="/usr/local/bin/monitor_ip.sh"
echo "#!/bin/bash" > $MONITOR_SCRIPT
echo "PREVIOUS_IP=\"\"" >> $MONITOR_SCRIPT
echo "while true; do" >> $MONITOR_SCRIPT
echo "  CURRENT_IP=$(curl -s ifconfig.me)" >> $MONITOR_SCRIPT
echo "  if [ \"\$CURRENT_IP\" != \"\$PREVIOUS_IP\" ]; then" >> $MONITOR_SCRIPT
echo "    PREVIOUS_IP=\$CURRENT_IP" >> $MONITOR_SCRIPT
echo "    for ((PORT=$START_PORT; PORT<$END_PORT; PORT++)); do" >> $MONITOR_SCRIPT
echo "      sed -i \"s/^[^:]*:\$PORT/\$CURRENT_IP:\$PORT/g\" $PROXY_LIST" >> $MONITOR_SCRIPT
echo "    done" >> $MONITOR_SCRIPT
echo "    sudo systemctl restart squid" >> $MONITOR_SCRIPT
echo "    enviar_email" >> $MONITOR_SCRIPT
echo "  fi" >> $MONITOR_SCRIPT
echo "  sleep 60" >> $MONITOR_SCRIPT
echo "done" >> $MONITOR_SCRIPT

sudo chmod +x $MONITOR_SCRIPT
sudo nohup bash $MONITOR_SCRIPT &

# Permitir portas no firewall
for ((PORT=$START_PORT; PORT<$END_PORT; PORT++)); do
  sudo ufw allow $PORT
  echo "Porta $PORT liberada no firewall."
done

# Liberar a porta 443 para o Squid
sudo ufw allow 443
echo "Porta 443 liberada no firewall."

# Reiniciar o Squid
sudo systemctl restart squid

echo "Configuração concluída! Proxies ativos e configurados para enviar atualizações por email."
