#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

# 检查Go环境
function check_go_installation() {
    if command -v go > /dev/null 2>&1; then
        echo "Go 环境已安装"
        return 0
    else
        echo "Go 环境未安装，正在安装..."
        return 1
    fi
}

# 节点安装功能
function install_node() {
    node_address="tcp://localhost:13457"
    install_nodejs_and_npm
    install_pm2

    # 检查curl是否安装，如果没有则安装
    if ! command -v curl > /dev/null; then
        sudo apt update && sudo apt install curl git -y
    fi

    # 更新和安装必要的软件
    sudo apt update && sudo apt upgrade -y
    sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip liblz4-tool -y

    # 安装 Go
    if ! check_go_installation; then
        sudo rm -rf /usr/local/go
        curl -L https://go.dev/dl/go1.22.0.linux-arm64.tar.gz | sudo tar -xzf - -C /usr/local
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
        source $HOME/.bash_profile
        go version
    fi

    # 安装所有二进制文件
    git clone https://github.com/a3165458/0g-evmos.git
    cd 0g-evmos
    make install
    evmosd version

    # 配置evmosd
    export MONIKER="kunkun_node"
    export WALLET_NAME="wallet"

    # 获取初始文件和地址簿
    cd $HOME
    evmosd init $MONIKER --chain-id zgtendermint_9000-1
    evmosd config chain-id zgtendermint_9000-1
    evmosd config node tcp://localhost:13457
    evmosd config keyring-backend os

    # 配置节点
    wget https://raw.githubusercontent.com/a3165458/0g.ai/main/gensis.json -O $HOME/.evmosd/config/genesis.json


    # 下载快照
    PEERS="813d6b668bc7e6b12141911205b0eade56eda18a@95.141.241.48:26656,187703290cb35ebabc909a054e6b50a5884f4e0a@158.220.114.57:13456,3c6854be5b111241594d4989884f66526e343128@5.189.170.145:26656,19b17dad1fc415922e1feb942d262735cbe1ed2e@95.216.42.217:26656,9859010f4b76f74d4091552fbbb520f4edcc9d96@95.111.243.106:13456,20d25530b222311b2114eff0934386f5063d411c@94.250.202.241:13456,20d25530b222311b2114eff0934386f5063d411c@31.220.102.142:13456" && \
    SEEDS="8c01665f88896bca44e8902a30e4278bed08033f@54.241.167.190:26656,b288e8b37f4b0dbd9a03e8ce926cd9c801aacf27@54.176.175.48:26656,8e20e8e88d504e67c7a3a58c2ea31d965aa2a890@54.193.250.204:26656,e50ac888b35175bfd4f999697bdeb5b7b52bfc06@54.215.187.94:26656" && \
    sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.evmosd/config/config.toml

    # 设置gas
    sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.00252aevmos\"/" $HOME/.evmosd/config/app.toml

    # 设置用户端口
    sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:13458\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:13457\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:13460\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:13456\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":13466\"%" $HOME/.evmosd/config/config.toml
    sed -i -e "s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:13417\"%; s%^address = \":8080\"%address = \":13480\"%; s%^address = \"localhost:9090\"%address = \"0.0.0.0:13490\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:13491\"%; s%:8545%:13445%; s%:8546%:13446%; s%:6065%:13465%" $HOME/.evmosd/config/app.toml
    echo "export OG_RPC_PORT=$node_address" >> $HOME/.bash_profile
    source $HOME/.bash_profile

    # 使用 PM2 启动节点进程
    pm2 start evmosd -- start && pm2 save && pm2 startup



    # 使用 pm2 停止 ogd 服务
    pm2 stop evmosd

    # 下载最新的快照
    wget -O latest_snapshot.tar.lz4 https://rpc-zero-gravity-testnet.trusted-point.com/latest_snapshot.tar.lz4

    # 备份当前的验证者状态文件
    cp $HOME/.evmosd/data/priv_validator_state.json $HOME/.evmosd/priv_validator_state.json.backup

    # 重置数据目录同时保留地址簿
    evmosd tendermint unsafe-reset-all --home $HOME/.evmosd --keep-addr-book

    # 将快照解压直接到 .evmosd 目录
    lz4 -d -c ./latest_snapshot.tar.lz4 | tar -xf - -C $HOME/.evmosd

    # 恢复验证者状态文件的备份
    mv $HOME/.evmosd/priv_validator_state.json.backup $HOME/.evmosd/data/priv_validator_state.json

    # 使用 pm2 重启 evmosd 服务并跟踪日志
    pm2 restart evmosd


    echo '====================== 安装完成,请退出脚本后执行 source $HOME/.bash_profile 以加载环境变量==========================='

}

# 查看0gai 服务状态
function check_service_status() {
    pm2 list
}

# 0gai 节点日志查询
function view_logs() {
    pm2 logs evmosd
}

# 卸载节点功能
function uninstall_node() {
    echo "你确定要卸载0g ai 节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY])
            echo "开始卸载节点程序..."
            pm2 stop evmosd && pm2 delete evmosd
            rm -rf $HOME/.evmosd $HOME/evmos $(which evmosd) && rm -rf 0g-evmos
            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 创建钱包
function add_wallet() {
    read -p "请输入你想设置的钱包名称: " wallet_name
    evmosd keys add $wallet_name
}

# 导入钱包
function import_wallet() {
    read -p "请输入你想设置的钱包名称: " wallet_name
    evmosd keys add $wallet_name --recover
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    evmosd query bank balances "$wallet_address"  --node $OG_RPC_PORT
}

# 查看节点同步状态
function check_sync_status() {
    evmosd status 2>&1 --node $OG_RPC_PORT  | jq .SyncInfo
}

# 创建验证者
function add_validator() {

read -p "请输入您的钱包名称: " wallet_name
read -p "请输入您想设置的验证者的名字: " validator_name
read -p "请输入您的验证者详情（例如'吊毛资本'）: " details


evmosd tx staking create-validator \
  --amount=1000000000000000aevmos \
  --pubkey=$(evmosd tendermint show-validator) \
  --moniker=$validator_name \
  --chain-id=zgtendermint_9000-1 \
  --commission-rate=0.05 \
  --commission-max-rate=0.10 \
  --commission-max-change-rate=0.01 \
  --min-self-delegation=1 \
  --from=$wallet_name \
  --identity="" \
  --website="" \
  --details="$details" \
  --gas=500000 \
  --gas-prices=99999aevmos \
  -y
}

function install_storage_node() {

    sudo apt-get update
    sudo apt-get install clang cmake build-essential git screen cargo -y


# 安装Go
    sudo rm -rf /usr/local/go
    curl -L https://go.dev/dl/go1.22.0.linux-arm64.tar.gz | sudo tar -xzf - -C /usr/local
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    source $HOME/.bash_profile


# 克隆仓库
git clone https://github.com/0glabs/0g-storage-node.git

#进入对应目录构建
cd 0g-storage-node
git submodule update --init

# 构建代码
cargo build --release

#后台运行
cd run


read -p "请输入你想导入的EVM钱包私钥，不要有0x: " minerkey

sed -i "s/miner_id = \"\"/miner_id = \"$(openssl rand -hex 32)\"/" config.toml
sed -i "s/miner_key = \"\"/miner_key = \"$minerkey\"/" config.toml




screen -dmS zgs_node_session ../target/release/zgs_node --config config.toml

echo '====================== 安装完成 ==========================='
echo '===进入对应路径:/0g-storage-node/run/log，使用tail -f logs文件名，查看logs 即可========================'

}


function install_storage_kv() {

# 克隆仓库
git clone https://github.com/0glabs/0g-storage-kv.git


#进入对应目录构建
cd 0g-storage-kv
git submodule update --init

# 构建代码
cargo build --release

#后台运行
cd run

echo "请输入RPC节点信息: "
read blockchain_rpc_endpoint


cat > config.toml <<EOF
stream_ids = ["000000000000000000000000000000000000000000000000000000000000f2bd", "000000000000000000000000000000000000000000000000000000000000f009", "00000000000000000000000000"]

db_dir = "db"
kv_db_dir = "kv.DB"

rpc_enabled = true
rpc_listen_address = "127.0.0.1:6789"
zgs_node_urls = "http://127.0.0.1:5678"

log_config_file = "log_config"

blockchain_rpc_endpoint = "$blockchain_rpc_endpoint"
log_contract_address = "0x22C1CaF8cbb671F220789184fda68BfD7eaA2eE1"
log_sync_start_block_number = 670000

EOF

echo "配置已成功写入 config.toml 文件"
screen -dmS storage_kv ../target/release/zgs_kv --config config.toml

}

# 给自己地址验证者质押
function delegate_self_validator() {
read -p "请输入质押代币数量(1000000为1个): " math
read -p "请输入钱包名称: " wallet_name
evmosd tx staking delegate $(evmosd keys show $wallet_name --bech val -a)  ${math}evmos --from $wallet_name --gas=500000 --gas-prices=99999aevmos --node $OG_RPC_PORT -y

}

# 查看存储节点同步状态
function check_storage_status() {
    tail -f "$(find ~/0g-storage-node/run/log/ -type f -printf '%T+ %p\n' | sort -r | head -n 1 | cut -d' ' -f2-)"
}

# 查看存储节点同步状态
function start_storage() {
cd 0g-storage-node/run && screen -dmS zgs_node_session ../target/release/zgs_node --config config.toml
echo '====================== 启动成功，请通过screen -r zgs_node_session 查询 ==========================='

}

# 转换ETH地址
function transfer_EIP() {
read -p "请输入你的钱包名称: " wallet_name
echo "0x$(evmosd debug addr $(evmosd keys show $wallet_name -a) | grep hex | awk '{print $3}')"

}

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
        echo "=======================验证节点功能================================"
        echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
        echo "节点社区 Discord 社群:https://discord.gg/GbMV5EcNWF"
        echo "退出脚本，请按键盘ctrl c退出即可"
        echo "请选择要执行的操作:"
        echo "1. 安装节点"
        echo "2. 创建钱包"
        echo "3. 导入钱包"
        echo "4. 查看钱包地址余额"
        echo "5. 查看节点同步状态"
        echo "6. 查看当前服务状态"
        echo "7. 运行日志查询"
        echo "8. 卸载节点"
        echo "9. 创建验证者"
        echo "10. 给自己验证者地址质押代币"
        echo "11. 转换ETH地址"
        echo "=======================存储节点功能================================"
        echo "12. 创建存储节点"
        echo "13. 查看存储节点日志"
        echo "14. 单独启动存储节点代码，适用于需要修改存储路径等功能修改过后使用"
        read -p "请输入选项（1-14）: " OPTION

        case $OPTION in
        1) install_node ;;
        2) add_wallet ;;
        3) import_wallet ;;
        4) check_balances ;;
        5) check_sync_status ;;
        6) check_service_status ;;
        7) view_logs ;;
        8) uninstall_node ;;
        9) add_validator ;;
        10) delegate_self_validator ;;
        11) transfer_EIP ;;
        12) install_storage_node ;;
        13) check_storage_status ;;
        14) start_storage ;;

        *) echo "无效选项。" ;;
        esac
        echo "按任意键返回主菜单..."
        read -n 1
    done

}

# 显示主菜单
main_menu
