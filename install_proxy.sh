#!/bin/bash

# Atualizar o sistema
echo "Atualizando o sistema..."
sudo apt update && sudo apt upgrade -y

# Instalar Squid e Apache2-utils
echo "Instalando o Squid e utilitários necessários..."
sudo apt install squid apache2-utils curl ufw -y

# Perguntar quantos proxies deseja gerar
echo "Quantos proxies você deseja gerar?"
read NUM_PROXIES

# Criar arquivo de autenticação
echo "Criando o arquivo de autenticação para $NUM_PROXIES proxies..."
sudo touch /etc/squid/usuarios_squid

# Criar arquivo para salvar as credenciais
CREDENCIAIS_FILE="/home/$(whoami)/proxies.txt"
echo "Salvando as credenciais em: $CREDENCIAIS_FILE"
echo "Credenciais geradas:" > $CREDENCIAIS_FILE

# Gerar múltiplos usuários e senhas
for i in $(seq 1 $NUM_PROXIES); do
    USER="usuario$(openssl rand -base64 6)"
    PASS=$(openssl rand -base64 12)
    
    # Adicionar usuário e senha no arquivo de autenticação
    echo "Usuário $i: $USER"
    echo "Senha $i: $PASS"
    sudo htpasswd -b /etc/squid/usuarios_squid $USER $PASS
    
    # Salvar as credenciais no arquivo txt
    echo "Usuário: $USER - Senha: $PASS" >> $CREDENCIAIS_FILE
done

# Configuração do Squid
echo "Configurando o Squid..."
sudo bash -c 'cat > /etc/squid/squid.conf <<EOF
http_port 3128
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/usuarios_squid
auth_param basic realm "Autenticacao Proxy"
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
visible_hostname proxy-servidor
EOF'

# Ajuste do firewall para permitir tráfego na porta do proxy
echo "Configurando o firewall..."
sudo ufw allow 3128/tcp

# Verificação e ajuste do IP público (caso mude o IP)
echo "Verificando o IP público..."
IP_ATUAL=$(curl -s https://api.ipify.org)

# Configurar o firewall para aceitar apenas o IP público atual
echo "Configurando firewall para o IP público: $IP_ATUAL..."
sudo ufw allow from $IP_ATUAL to any port 3128 proto tcp

# Reiniciar o Squid para aplicar as configurações
echo "Reiniciando o Squid..."
sudo systemctl restart squid

# Verificar status do Squid
echo "Verificando o status do Squid..."
sudo systemctl status squid --no-pager

# Exibir o caminho para o arquivo de credenciais
echo "Configuração concluída!"
echo "O proxy está funcionando na porta 3128."
echo "As credenciais foram salvas em: $CREDENCIAIS_FILE"
