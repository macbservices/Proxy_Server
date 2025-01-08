#!/bin/bash

# Função para gerar a senha aleatória
generate_password() {
    openssl rand -base64 12
}

# Função para gerar o nome de usuário aleatório
generate_username() {
    openssl rand -base64 8
}

# Função para obter o IP público da VPS
get_public_ip() {
    PUBLIC_IP=$(curl -s https://api.ipify.org)
    echo $PUBLIC_IP
}

# Função para configurar o Squid para permitir o IP, porta e usuário
configure_squid() {
    local ip="$1"
    local port="$2"
    local username="$3"
    local password="$4"
    
    # Caminho para o arquivo de configuração do Squid
    SQUID_CONFIG="/etc/squid/squid.conf"

    # Adicionar exceção de IP, porta e usuário na configuração
    echo "acl allowed_ips src $ip" | sudo tee -a $SQUID_CONFIG > /dev/null
    echo "acl allowed_ports port $port" | sudo tee -a $SQUID_CONFIG > /dev/null
    echo "acl allowed_users proxy_auth $username" | sudo tee -a $SQUID_CONFIG > /dev/null

    # Permitir acesso para os IPs, portas e usuários configurados
    echo "http_access allow allowed_ips allowed_ports allowed_users" | sudo tee -a $SQUID_CONFIG > /dev/null

    # Reiniciar o Squid para aplicar as mudanças
    sudo systemctl restart squid
}

# Função para limpar configurações antigas no Squid
clean_squid_config() {
    # Caminho para o arquivo de configuração do Squid
    SQUID_CONFIG="/etc/squid/squid.conf"
    
    # Remover as exceções de IP, porta e usuário
    sudo sed -i '/acl allowed_ips src/d' $SQUID_CONFIG
    sudo sed -i '/acl allowed_ports port/d' $SQUID_CONFIG
    sudo sed -i '/acl allowed_users proxy_auth/d' $SQUID_CONFIG
    sudo sed -i '/http_access allow allowed_ips allowed_ports allowed_users/d' $SQUID_CONFIG
    
    # Reiniciar o Squid para aplicar as mudanças
    sudo systemctl restart squid
}

# Função principal para criar proxies
create_proxy() {
    echo "Quantos proxies você deseja criar?"
    read num_proxies

    # Caminho para salvar a lista de proxies
    LIST_PATH="/tmp/proxy_list.txt"

    # Verificar se já existe uma lista anterior e excluí-la
    if [ -f "$LIST_PATH" ]; then
        echo "Lista anterior encontrada. Excluindo..."
        rm $LIST_PATH
    fi

    # Limpar configurações antigas do Squid antes de adicionar novas exceções
    clean_squid_config

    COUNTER=1

    # Loop para criar múltiplos proxies
    for i in $(seq 1 $num_proxies); do
        IP=$(get_public_ip)
        PORT=$((20000 + COUNTER))
        USERNAME=$(generate_username)
        PASSWORD=$(generate_password)

        # Adicionar a entrada no arquivo de configuração do Squid
        configure_squid $IP $PORT $USERNAME $PASSWORD

        # Salvar os proxies gerados no arquivo de lista
        echo "$IP:$PORT:$USERNAME:$PASSWORD" >> $LIST_PATH

        echo "Proxy $COUNTER criado com sucesso!"
        COUNTER=$((COUNTER + 1))
    done

    echo "Lista de proxies salva em $LIST_PATH"
}

# Chamar a função para criar os proxies
create_proxy
