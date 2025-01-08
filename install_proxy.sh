#!/bin/bash

# Script para configurar um servidor de proxy simples utilizando Shadowsocks
# Inclui geração de lista de proxies com IP, porta, usuário e senha, e grava em um arquivo local.

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
sudo apt install -y shadowsocks-libev curl msmtp msmtp-mta

# Configuração do msmtp (cliente de envio de email)
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

# Configuração do Shadowsocks
echo "Criando configuração do Shadowsocks..."
SS_CONFIG="/etc/shadowsocks-libev/config.json"
sudo mkdir -p /etc/shadowsocks-libev

cat <<EOL | sudo tee $SS_CONFIG > /dev/null
{
    "server": "0.0.0.0",
    "server_port": 443,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "sua_senha_forte_aqui",
    "timeout": 300,
    "method": "aes-256-gcm"
}
EOL

# Iniciar o Shadowsocks
sudo systemctl start shadowsocks-libev
sudo systemctl enable shadowsocks-libev

# Gerar a lista de proxies
PROXY_LIST="/tmp/proxy_list.txt"
> $PROXY_LIST  # Limpar lista antiga

echo "Gerando proxies..."

for ((i=1; i<=100; i++)); do
    IP=$(curl -s ifconfig.me)  # Captura o IP atual do servidor
    PORT=$((20000 + i))         # Definindo a porta a ser usada
    USER=$(openssl rand -hex 4) # Gerar usuário seguro
    PASS=$(openssl rand -hex 8) # Gerar senha segura
    echo "$IP:$PORT:$USER:$PASS" >> $PROXY_LIST
    echo "Proxy $i: $IP:$PORT:$USER:$PASS"  # Exibe os proxies criados
done

# Função para enviar a lista de proxies por email
enviar_email() {
  echo "Enviando lista de proxies por email..."
  cat <<EOL | msmtp -t
To: $RECIPIENT
From: $GMAIL_USER
Subject: Lista de Proxies Atualizada

Segue a lista dos proxies atualizados:

$(cat $PROXY_LIST)
EOL
}

enviar_email  # Enviar email inicial

# Exibir onde o arquivo de proxies foi salvo
echo "A lista de proxies foi salva em: $PROXY_LIST"
echo "Você pode acessar o arquivo diretamente para visualizar a lista completa."

# Reiniciar o Shadowsocks para garantir que tudo esteja em funcionamento
echo "Reiniciando o Shadowsocks..."
sudo systemctl restart shadowsocks-libev

echo "Configuração concluída! Proxies ativos e configurados."
