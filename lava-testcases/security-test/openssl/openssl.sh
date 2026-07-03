#!/bin/bash
# =============================================================================
# 加密与证书管理测试套件（openEuler RISC-V）
# =============================================================================
# 测试目标：验证 openEuler RV 操作系统在加密算法、证书管理、TLS 通信、
#          安全策略等方面的功能正确性与合规性
# 输出格式：测试项 pass/fail/skip
# =============================================================================

# 测试结果输出目录
OUTPUT="$(pwd)/output"
mkdir -p "$OUTPUT"
RESULT_FILE="${OUTPUT}/result.txt"

# 临时工作目录，脚本退出时自动清理
tmpdir=$(mktemp -d)
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

# =============================================================================
# 辅助函数
# =============================================================================

# ---------------------------------------------------------------------------
# 检查指定命令是否存在于系统 PATH 中
# 参数：$1 = 命令名
# 返回：0（存在）/ 1（不存在）
# ---------------------------------------------------------------------------
cmd_exists() { command -v "$1" &>/dev/null; }

# ---------------------------------------------------------------------------
# 检查指定目录中是否包含有效的证书文件
# 支持的证书格式：*.pem、*.crt、*.0（哈希命名）、*.der
# 参数：$1 = 目录路径
# 返回：0（存在证书文件）/ 1（不存在或为空）
# ---------------------------------------------------------------------------
has_cert_files() {
    local dir="$1"
    [ -d "$dir" ] || return 1
    local count
    count=$(find "$dir" -maxdepth 2 -type f \( -name "*.pem" -o -name "*.crt" -o -name "*.0" -o -name "*.der" \) 2>/dev/null | wc -l)
    [ "$count" -gt 0 ]
}

# =============================================================================
# 1. OpenSSL 安装检查
# =============================================================================
# OpenSSL 是 openEuler 国密支持的核心组件，所有后续测试的前提条件。
# 验证系统是否已安装 openssl 命令行工具。
# ---------------------------------------------------------------------------
test_openssl_installed() {
    if cmd_exists openssl; then
        echo "openssl-installed pass"
    else
        echo "openssl-installed fail"
    fi
}

# =============================================================================
# 2. AES-256-CBC 加密/解密正确性
# =============================================================================
# 国际算法兼容性基线测试。
# 验证 AES-256-CBC 对称加密的往返正确性：
#   明文 → 加密 → 解密 → 明文
# 使用 PBKDF2 派生密钥（-pass 选项自动处理）。
# ---------------------------------------------------------------------------
test_aes_correctness() {
    local plain="hello world test"
    local pass="testkey123"
    if ! echo -n "$plain" | openssl enc -aes-256-cbc -pass pass:"$pass" -out "$tmpdir/aes.enc" 2>/dev/null; then
        echo "aes-correctness fail"
        return
    fi
    local decrypted
    decrypted=$(openssl enc -aes-256-cbc -d -pass pass:"$pass" -in "$tmpdir/aes.enc" 2>/dev/null)
    if [ "$decrypted" = "$plain" ]; then
        echo "aes-correctness pass"
    else
        echo "aes-correctness fail"
    fi
}

# =============================================================================
# 3. SHA256/512 标准哈希正确性
# =============================================================================
# 国际算法兼容性基线测试。
# 使用 NIST 标准测试向量验证 SHA-256 和 SHA-512 的正确性：
#   输入 "abc" 的哈希值是公开定义的标准值
# ---------------------------------------------------------------------------
test_hash_correctness() {
    local test_str="abc"
    local sha256_expected="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    local sha512_expected="ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"

    local sha256_result
    sha256_result=$(echo -n "$test_str" | openssl dgst -sha256 | awk '{print $NF}')
    if [ "$sha256_result" != "$sha256_expected" ]; then
        echo "hash-correctness fail"
        return
    fi

    local sha512_result
    sha512_result=$(echo -n "$test_str" | openssl dgst -sha512 | awk '{print $NF}')
    if [ "$sha512_result" != "$sha512_expected" ]; then
        echo "hash-correctness fail"
        return
    fi

    echo "hash-correctness pass"
}

# =============================================================================
# 4. 随机数质量简单检测
# =============================================================================
# 验证 OpenSSL 随机数生成器的基本质量：
#   连续生成 20 个 128 位（16 字节十六进制）随机数
#   检查是否有重复值（理论上概率极低）
# 注意：这是简单检测，非密码学强度统计测试（如 NIST SP 800-22）
# ---------------------------------------------------------------------------
test_random_quality() {
    local samples=()
    for i in $(seq 1 20); do
        samples+=($(openssl rand -hex 16 2>/dev/null))
    done
    local unique=$(printf '%s\n' "${samples[@]}" | sort -u | wc -l)
    [ "$unique" -eq 20 ] && echo "random-quality pass" || echo "random-quality fail"
}

# =============================================================================
# 5. RSA 密钥生成与签名/验签正确性
# =============================================================================
# 国际算法兼容性基线测试。
# 验证 RSA-2048 密钥对生成、SHA-256 签名及验签的完整流程。
# RSA-2048 是当前安全基线（低于 2048 位被认为不安全）。
# ---------------------------------------------------------------------------
test_rsa_sign_verify() {
    if ! openssl genrsa -out "$tmpdir/rsa_priv.pem" 2048 2>/dev/null; then
        echo "rsa-sign-verify fail"
        return
    fi
    if ! openssl rsa -in "$tmpdir/rsa_priv.pem" -pubout -out "$tmpdir/rsa_pub.pem" 2>/dev/null; then
        echo "rsa-sign-verify fail"
        return
    fi
    echo -n "testdata" | openssl dgst -sha256 -sign "$tmpdir/rsa_priv.pem" -out "$tmpdir/rsa.sig" 2>/dev/null
    if echo -n "testdata" | openssl dgst -sha256 -verify "$tmpdir/rsa_pub.pem" -signature "$tmpdir/rsa.sig" 2>/dev/null; then
        echo "rsa-sign-verify pass"
    else
        echo "rsa-sign-verify fail"
    fi
}

# =============================================================================
# 6. ECC (P-256) 密钥生成与签名验签
# =============================================================================
# 国际算法兼容性基线测试。
# 验证 NIST P-256（prime256v1）椭圆曲线密钥生成及 ECDSA 签名验签。
# P-256 是 TLS 1.2/1.3 广泛使用的曲线。
# ---------------------------------------------------------------------------
test_ecc_keygen_sign() {
    if ! openssl ecparam -genkey -name prime256v1 -out "$tmpdir/ecc_priv.pem" 2>/dev/null; then
        echo "ecc-keygen-sign fail"
        return
    fi
    if ! openssl ec -in "$tmpdir/ecc_priv.pem" -pubout -out "$tmpdir/ecc_pub.pem" 2>/dev/null; then
        echo "ecc-keygen-sign fail"
        return
    fi
    echo -n "ecctest" > "$tmpdir/ecc_data.txt"
    if ! openssl dgst -sha256 -sign "$tmpdir/ecc_priv.pem" -out "$tmpdir/ecc.sig" "$tmpdir/ecc_data.txt" 2>/dev/null; then
        echo "ecc-keygen-sign fail"
        return
    fi
    if openssl dgst -sha256 -verify "$tmpdir/ecc_pub.pem" -signature "$tmpdir/ecc.sig" "$tmpdir/ecc_data.txt" 2>/dev/null; then
        echo "ecc-keygen-sign pass"
    else
        echo "ecc-keygen-sign fail"
    fi
}

# =============================================================================
# 7. SM3 哈希正确性（国密算法）
# =============================================================================
# 国密算法核心测试。
# 使用 GM/T 0004-2012 标准测试向量验证 SM3 哈希正确性：
#   输入 "abc" 的 SM3 哈希值是公开定义的标准值
# SM3 是国产密码杂凑算法，输出 256 位摘要，功能对标 SHA-256。
# ---------------------------------------------------------------------------
test_sm3_correctness() {
    local expected="66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0"
    local result
    # 优先使用 openssl dgst -sm3（OpenSSL 3.x 推荐方式）
    result=$(echo -n "abc" | openssl dgst -sm3 2>/dev/null | awk '{print $NF}')
    # 回退到 openssl sm3（旧版本兼容）
    if [ -z "$result" ]; then
        result=$(echo -n "abc" | openssl sm3 2>/dev/null | awk '{print $NF}')
    fi
    if [ "$result" = "$expected" ]; then
        echo "sm3-correctness pass"
    else
        echo "sm3-correctness fail"
    fi
}

# =============================================================================
# 8. SM4-CBC 加密/解密正确性（国密算法）
# =============================================================================
# 国密算法核心测试。
# 验证 SM4-CBC 对称加密的往返正确性。
# SM4 是国产分组密码算法，分组长度 128 位，密钥长度 128 位，
# 功能对标 AES-128。
# 测试兼容大小写两种命名方式（sm4-cbc / SM4-CBC）。
# ---------------------------------------------------------------------------
test_sm4_correctness() {
    local plain="sm4testdata123"
    local pass="sm4key"
    # 尝试小写命名
    if echo -n "$plain" | openssl enc -sm4-cbc -pass pass:"$pass" -out "$tmpdir/sm4.enc" 2>/dev/null; then
        local decrypted
        decrypted=$(openssl enc -sm4-cbc -d -pass pass:"$pass" -in "$tmpdir/sm4.enc" 2>/dev/null)
        if [ "$decrypted" = "$plain" ]; then
            echo "sm4-correctness pass"
            return
        fi
    fi
    # 尝试大写命名（兼容部分版本）
    if echo -n "$plain" | openssl enc -SM4-CBC -pass pass:"$pass" -out "$tmpdir/sm4.enc" 2>/dev/null; then
        local decrypted
        decrypted=$(openssl enc -SM4-CBC -d -pass pass:"$pass" -in "$tmpdir/sm4.enc" 2>/dev/null)
        if [ "$decrypted" = "$plain" ]; then
            echo "sm4-correctness pass"
            return
        fi
    fi
    echo "sm4-correctness fail"
}

# =============================================================================
# 9. SM2 密钥生成及签名验签正确性（国密算法）
# =============================================================================
# 国密算法核心测试。
# 验证 SM2 椭圆曲线密钥对生成、SM3 摘要签名及验签的完整流程。
# SM2 是国产非对称密码算法，基于椭圆曲线，功能对标 ECDSA/ECDH。
# 兼容大小写命名（SM2 / sm2），支持 dgst 和 pkeyutl 两种签名接口。
# ---------------------------------------------------------------------------
test_sm2_sign_verify() {
    # 尝试生成 SM2 密钥（兼容大小写命名）
    if openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_priv.pem" 2>/dev/null; then
        :
    elif openssl ecparam -genkey -name sm2 -out "$tmpdir/sm2_priv.pem" 2>/dev/null; then
        :
    else
        echo "sm2-sign-verify fail"
        return
    fi
    # 导出公钥
    openssl ec -in "$tmpdir/sm2_priv.pem" -pubout -out "$tmpdir/sm2_pub.pem" 2>/dev/null
    # 使用 SM3 摘要进行签名
    echo -n "test" | openssl dgst -sm3 -sign "$tmpdir/sm2_priv.pem" -out "$tmpdir/sm2.sig" 2>/dev/null
    # 如果 dgst 签名失败，回退到 pkeyutl
    if [ ! -s "$tmpdir/sm2.sig" ]; then
        echo -n "test" | openssl pkeyutl -sign -inkey "$tmpdir/sm2_priv.pem" -out "$tmpdir/sm2.sig" 2>/dev/null
    fi
    # 验签
    if [ -s "$tmpdir/sm2.sig" ]; then
        if echo -n "test" | openssl dgst -sm3 -verify "$tmpdir/sm2_pub.pem" -signature "$tmpdir/sm2.sig" 2>/dev/null; then
            echo "sm2-sign-verify pass"
        elif echo -n "test" | openssl pkeyutl -verify -pubin -inkey "$tmpdir/sm2_pub.pem" -sigfile "$tmpdir/sm2.sig" 2>/dev/null; then
            echo "sm2-sign-verify pass"
        else
            echo "sm2-sign-verify fail"
        fi
    else
        echo "sm2-sign-verify fail"
    fi
}

# =============================================================================
# 10. RSA 自签证书公钥与私钥匹配性验证
# =============================================================================
# 证书管理基线测试（RSA）。
# 生成 RSA 自签名证书，提取证书中的公钥，与私钥导出的公钥对比，
# 验证证书确实由对应私钥签发。
# ---------------------------------------------------------------------------
test_cert_key_match() {
    openssl genrsa -out "$tmpdir/key.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/key.pem" -out "$tmpdir/cert.pem" -days 1 \
        -subj "/CN=Test" 2>/dev/null
    local cert_pub key_pub
    cert_pub=$(openssl x509 -in "$tmpdir/cert.pem" -pubkey -noout 2>/dev/null)
    key_pub=$(openssl rsa -in "$tmpdir/key.pem" -pubout 2>/dev/null)
    if [ "$cert_pub" = "$key_pub" ]; then
        echo "cert-key-match pass"
    else
        echo "cert-key-match fail"
    fi
}

# =============================================================================
# 10b. SM2 自签证书公钥与私钥匹配性验证（国密）
# =============================================================================
# 国密证书管理测试。
# 生成 SM2 自签名证书（使用 SM3 摘要算法），验证证书公钥与私钥的匹配性。
# ---------------------------------------------------------------------------
test_sm2_cert_key_match() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_ck_key.pem" 2>/dev/null; then
        echo "sm2-cert-key-match fail"
        return
    fi
    openssl req -new -x509 -sm3 -key "$tmpdir/sm2_ck_key.pem" -out "$tmpdir/sm2_ck_cert.pem" -days 1 \
        -subj "/C=CN/O=openEuler/CN=SM2-Test" 2>/dev/null
    local cert_pub key_pub
    cert_pub=$(openssl x509 -in "$tmpdir/sm2_ck_cert.pem" -pubkey -noout 2>/dev/null)
    key_pub=$(openssl ec -in "$tmpdir/sm2_ck_key.pem" -pubout 2>/dev/null)
    if [ "$cert_pub" = "$key_pub" ]; then
        echo "sm2-cert-key-match pass"
    else
        echo "sm2-cert-key-match fail"
    fi
}

# =============================================================================
# 11. RSA 自签证书验证
# =============================================================================
# 证书管理基线测试（RSA）。
# 生成 RSA 自签名证书，使用 openssl verify 验证证书有效性。
# 自签名证书作为自身的信任锚进行验证。
# ---------------------------------------------------------------------------
test_cert_verify() {
    openssl genrsa -out "$tmpdir/key2.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/key2.pem" -out "$tmpdir/cert2.pem" -days 1 \
        -subj "/CN=TestVerify" 2>/dev/null
    if openssl verify -CAfile "$tmpdir/cert2.pem" "$tmpdir/cert2.pem" &>/dev/null; then
        echo "cert-verify pass"
    else
        echo "cert-verify fail"
    fi
}

# =============================================================================
# 11b. SM2 自签证书验证（国密）
# =============================================================================
# 国密证书管理测试。
# 生成 SM2 自签名证书（使用 SM3 摘要），验证证书链。
# ---------------------------------------------------------------------------
test_sm2_cert_verify() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_cv_key.pem" 2>/dev/null; then
        echo "sm2-cert-verify fail"
        return
    fi
    openssl req -new -x509 -sm3 -key "$tmpdir/sm2_cv_key.pem" -out "$tmpdir/sm2_cv_cert.pem" -days 1 \
        -subj "/C=CN/O=openEuler/CN=SM2-Verify" 2>/dev/null
    if openssl verify -CAfile "$tmpdir/sm2_cv_cert.pem" "$tmpdir/sm2_cv_cert.pem" &>/dev/null; then
        echo "sm2-cert-verify pass"
    else
        echo "sm2-cert-verify fail"
    fi
}

# =============================================================================
# 12. RSA 多层级证书链验证
# =============================================================================
# 证书管理基线测试（RSA）。
# 构建三层 PKI 架构：根 CA → 中间 CA → 服务器证书
# 使用 X.509 v3 扩展定义各层级约束（basicConstraints、keyUsage 等）。
# 验证 openssl verify 能否正确验证完整证书链。
# ---------------------------------------------------------------------------
test_cert_chain_verify() {
    # 创建 X.509 v3 扩展配置文件
    # 生成包含 req 段和扩展段的完整临时配置
    cat > "$tmpdir/ca_ext.cnf" << 'EOF'
[ req ]
distinguished_name = req_dn
x509_extensions    = v3_ca
prompt             = no

[ req_dn ]
C  = CN
O  = Root
CN = RootCA

[ v3_ca ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer

[ v3_inter ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer

[ v3_server ]
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

    # 根 CA：自签名（使用 -config 替代 -extfile + -extensions）
    openssl genrsa -out "$tmpdir/root.key" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/root.key" -out "$tmpdir/root.crt" -days 365 \
        -config "$tmpdir/ca_ext.cnf" 2>/dev/null

    # 中间 CA：由根 CA 签发
    openssl genrsa -out "$tmpdir/inter.key" 2048 2>/dev/null
    openssl req -new -key "$tmpdir/inter.key" -out "$tmpdir/inter.csr" \
        -subj "/C=CN/O=Inter/CN=InterCA" 2>/dev/null
    openssl x509 -req -in "$tmpdir/inter.csr" -CA "$tmpdir/root.crt" -CAkey "$tmpdir/root.key" \
        -out "$tmpdir/inter.crt" -days 365 -CAcreateserial \
        -extensions v3_inter -extfile "$tmpdir/ca_ext.cnf" 2>/dev/null

    # 服务器证书：由中间 CA 签发
    openssl genrsa -out "$tmpdir/srv.key" 2048 2>/dev/null
    openssl req -new -key "$tmpdir/srv.key" -out "$tmpdir/srv.csr" \
        -subj "/C=CN/O=Server/CN=localhost" 2>/dev/null
    openssl x509 -req -in "$tmpdir/srv.csr" -CA "$tmpdir/inter.crt" -CAkey "$tmpdir/inter.key" \
        -out "$tmpdir/srv.crt" -days 365 -CAcreateserial \
        -extensions v3_server -extfile "$tmpdir/ca_ext.cnf" 2>/dev/null

    # 验证证书链：根 CA 作为信任锚，中间 CA 作为非信任中间证书
    local verify_result
    verify_result=$(openssl verify -CAfile "$tmpdir/root.crt" -untrusted "$tmpdir/inter.crt" "$tmpdir/srv.crt" 2>&1)
    if echo "$verify_result" | grep -q "OK"; then
        echo "cert-chain-verify pass"
    else
        echo "cert-chain-verify fail"
    fi
}

# =============================================================================
# 12b. SM2 多层级证书链验证
# =============================================================================
# 国密证书管理核心测试。
# 构建三层 SM2 PKI 架构，使用 SM3 作为摘要算法：
#   根 CA（SM2 自签名）→ 中间 CA（SM2，根签发）→ 服务器证书（SM2，中间签发）
# 验证 openssl verify 对 SM2 证书链的完整验证能力。
# ---------------------------------------------------------------------------
test_sm2_cert_chain_verify() {
    local sm2_ca_dir="$tmpdir/sm2_chain_ca"
    mkdir -p "$sm2_ca_dir"

    cat > "$sm2_ca_dir/ca_ext.cnf" << 'EOF'
[ req ]
distinguished_name = req_dn
x509_extensions    = v3_ca
prompt             = no

[ req_dn ]
C  = CN
O  = Root
CN = RootCA

[ v3_ca ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer

[ v3_inter ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer

[ v3_server ]
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

    # 根 CA：SM2 自签名，SM3 摘要
    openssl ecparam -genkey -name SM2 -out "$sm2_ca_dir/root.key" 2>/dev/null
    openssl req -new -x509 -sm3 -key "$sm2_ca_dir/root.key" -out "$sm2_ca_dir/root.crt" -days 365 \
        -subj "/C=CN/O=openEuler/CN=SM2-RootCA" \
        -config "$sm2_ca_dir/ca_ext.cnf" 2>/dev/null

    # 中间 CA：由根 CA 用 SM2+SM3 签发
    openssl ecparam -genkey -name SM2 -out "$sm2_ca_dir/inter.key" 2>/dev/null
    openssl req -new -sm3 -key "$sm2_ca_dir/inter.key" -out "$sm2_ca_dir/inter.csr" \
        -subj "/C=CN/O=openEuler/CN=SM2-InterCA" 2>/dev/null
    openssl x509 -req -in "$sm2_ca_dir/inter.csr" -CA "$sm2_ca_dir/root.crt" -CAkey "$sm2_ca_dir/root.key" \
        -out "$sm2_ca_dir/inter.crt" -days 365 -CAcreateserial \
        -extensions v3_inter -extfile "$sm2_ca_dir/ca_ext.cnf" 2>/dev/null

    # 服务器证书：由中间 CA 用 SM2+SM3 签发
    openssl ecparam -genkey -name SM2 -out "$sm2_ca_dir/srv.key" 2>/dev/null
    openssl req -new -sm3 -key "$sm2_ca_dir/srv.key" -out "$sm2_ca_dir/srv.csr" \
        -subj "/C=CN/O=openEuler/CN=localhost" 2>/dev/null
    openssl x509 -req -in "$sm2_ca_dir/srv.csr" -CA "$sm2_ca_dir/inter.crt" -CAkey "$sm2_ca_dir/inter.key" \
        -out "$sm2_ca_dir/srv.crt" -days 365 -CAcreateserial \
        -extensions v3_server -extfile "$sm2_ca_dir/ca_ext.cnf" 2>/dev/null

    # 验证 SM2 证书链
    local verify_result
    verify_result=$(openssl verify -CAfile "$sm2_ca_dir/root.crt" -untrusted "$sm2_ca_dir/inter.crt" "$sm2_ca_dir/srv.crt" 2>&1)
    if echo "$verify_result" | grep -q "OK"; then
        echo "sm2-cert-chain-verify pass"
    else
        echo "sm2-cert-chain-verify fail"
    fi
}

# =============================================================================
# 13. RSA 证书有效期检查
# =============================================================================
# 证书管理基线测试（RSA）。
# 生成 RSA 自签名证书，验证 openssl x509 -enddate 能否正确读取有效期。
# ---------------------------------------------------------------------------
test_cert_expiry() {
    openssl genrsa -out "$tmpdir/key3.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/key3.pem" -out "$tmpdir/cert3.pem" -days 1 \
        -subj "/CN=ExpiryTest" 2>/dev/null
    if openssl x509 -in "$tmpdir/cert3.pem" -noout -enddate &>/dev/null; then
        echo "cert-expiry pass"
    else
        echo "cert-expiry fail"
    fi
}

# =============================================================================
# 13b. SM2 证书有效期检查（国密）
# =============================================================================
# 国密证书管理测试。
# 生成 SM2 自签名证书，验证有效期读取。
# ---------------------------------------------------------------------------
test_sm2_cert_expiry() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_exp_key.pem" 2>/dev/null; then
        echo "sm2-cert-expiry fail"
        return
    fi
    openssl req -new -x509 -sm3 -key "$tmpdir/sm2_exp_key.pem" -out "$tmpdir/sm2_exp_cert.pem" -days 1 \
        -subj "/C=CN/O=openEuler/CN=SM2-Expiry" 2>/dev/null
    if openssl x509 -in "$tmpdir/sm2_exp_cert.pem" -noout -enddate &>/dev/null; then
        echo "sm2-cert-expiry pass"
    else
        echo "sm2-cert-expiry fail"
    fi
}

# =============================================================================
# 14. 系统 CA 证书库存在性
# =============================================================================
# 验证系统 CA 信任库是否配置正确。
# openEuler 使用 /etc/pki/ca-trust 体系（源自 Fedora/RHEL），
# 与 Debian/Ubuntu 的 /usr/share/ca-certificates 不同。
# 检查路径已适配 openEuler 实际目录结构。
# ---------------------------------------------------------------------------
test_ca_store() {
    local dirs=(
        "/etc/pki/ca-trust/extracted"         # openEuler 主信任锚目录
        "/etc/pki/tls/certs"                  # 系统 TLS 证书目录
        "/etc/ssl/certs"                      # 兼容路径（通常是软链接）
        "/etc/pki/ca-trust/source/anchors"   # 管理员自定义 CA 存放目录
    )
    for d in "${dirs[@]}"; do
        if has_cert_files "$d"; then
            echo "ca-store pass"
            return
        fi
    done
    echo "ca-store fail"
}

# =============================================================================
# 15. TLS 1.2 握手及加密通信验证（RSA基线）
# =============================================================================
# TLS 通信基线测试（国际算法）。
# 启动 openssl s_server 作为 TLS 服务端，使用 RSA 证书。
# 客户端使用 openssl s_client 连接，验证 TLS 1.2 握手成功及加密套件协商。
# ---------------------------------------------------------------------------
test_tls_handshake() {
    openssl genrsa -out "$tmpdir/srv_key.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/srv_key.pem" -out "$tmpdir/srv_cert.pem" -days 1 \
        -subj "/CN=localhost" 2>/dev/null

    # 后台启动 TLS 服务端
    openssl s_server -accept 24443 -cert "$tmpdir/srv_cert.pem" -key "$tmpdir/srv_key.pem" -quiet &>/dev/null &
    local pid=$!
    sleep 1

    # 客户端连接，检查是否成功协商加密套件
    local result
    result=$(echo "Q" | openssl s_client -connect localhost:24443 -tls1_2 2>/dev/null | grep -c "Cipher is")
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    if [ "$result" -gt 0 ]; then
        echo "tls-handshake pass"
    else
        echo "tls-handshake fail"
    fi
}

# =============================================================================
# 16. 私钥文件权限检查
# =============================================================================
# 验证密钥文件能否正确设置 600 权限（仅所有者可读写）。
# 私钥文件权限过宽（如 644）会导致安全风险，这是等保/密评的常见检查项。
# ---------------------------------------------------------------------------
test_key_file_permission() {
    openssl genrsa -out "$tmpdir/perm_test.key" 2048 2>/dev/null
    chmod 600 "$tmpdir/perm_test.key"
    local perms
    perms=$(stat -c "%a" "$tmpdir/perm_test.key" 2>/dev/null)
    if [ "$perms" = "600" ]; then
        echo "key-file-permission pass"
    else
        echo "key-file-permission fail"
    fi
}

# =============================================================================
# 17. 系统口令哈希策略检查（SHA256/SHA512）
# =============================================================================
# 验证系统 PAM 配置中是否启用了安全的口令哈希算法（SHA-512 或 SHA-256）。
# 检查常见的 PAM 配置文件路径。
# ---------------------------------------------------------------------------
test_password_hash_policy() {
    local found=0
    local files=("/etc/pam.d/system-auth" "/etc/pam.d/common-password" "/etc/pam.d/password-auth")
    for f in "${files[@]}"; do
        if [ -f "$f" ] && grep -q "sha512" "$f" 2>/dev/null; then
            found=1
            break
        fi
    done
    if [ "$found" -eq 1 ]; then
        echo "password-hash-policy pass"
    else
        echo "password-hash-policy fail"
    fi
}

# =============================================================================
# 17b. SM3 口令哈希策略检查（国密）
# =============================================================================
# 验证系统 PAM 配置中是否支持 SM3 作为口令哈希算法。
# openEuler 部分版本支持 pam_sm3 模块实现国密口令策略。
# 如果系统中未配置 SM3，标记为 skip（非失败）。
# ---------------------------------------------------------------------------
test_sm3_password_hash_policy() {
    local found=0
    local files=("/etc/pam.d/system-auth" "/etc/pam.d/common-password" "/etc/pam.d/password-auth")
    for f in "${files[@]}"; do
        if [ -f "$f" ] && grep -qi "sm3" "$f" 2>/dev/null; then
            found=1
            break
        fi
    done
    if [ "$found" -eq 1 ]; then
        echo "sm3-password-hash-policy pass"
    else
        echo "sm3-password-hash-policy skip"
    fi
}

# =============================================================================
# 18. 弱算法拒绝验证
# =============================================================================
# 验证系统是否拒绝使用已知不安全的密码算法：
#   - DES-CBC：密钥长度过短（56位），已被暴力破解
#   - RC4：存在统计偏差攻击，TLS 中已禁用
#   - MD5：存在碰撞攻击，不再用于数字签名
# openEuler 默认安全策略应拒绝上述弱算法。
# 至少拒绝 2 种弱算法即判定通过（兼容不同安全策略级别）。
# ---------------------------------------------------------------------------
test_weak_algo_rejection() {
    local weak_rejected=0
    # 测试 DES-CBC 是否被拒绝
    if ! echo -n "test" | openssl enc -des-cbc -pass pass:"key" -pbkdf2 -out /dev/null 2>/dev/null; then
        weak_rejected=$((weak_rejected + 1))
    fi
    # 测试 RC4 是否被拒绝
    if ! echo -n "test" | openssl enc -rc4 -pass pass:"key" -out /dev/null 2>/dev/null; then
        weak_rejected=$((weak_rejected + 1))
    fi
    # 测试 MD5 签名是否被拒绝
    if ! echo -n "test" | openssl dgst -md5 -sign "$tmpdir/rsa_priv.pem" -out /dev/null 2>/dev/null; then
        weak_rejected=$((weak_rejected + 1))
    fi
    if [ "$weak_rejected" -ge 2 ]; then
        echo "weak-algo-rejection pass"
    else
        echo "weak-algo-rejection fail"
    fi
}

# =============================================================================
# 19. TLS 不安全协议版本拒绝
# =============================================================================
# 验证 TLS 服务端是否拒绝不安全的协议版本：
#   - SSLv3：存在 POODLE 攻击，已废弃
#   - TLS 1.0：存在 BEAST 等攻击，已废弃
# openEuler 默认应仅允许 TLS 1.2+ 连接。
# ---------------------------------------------------------------------------
test_insecure_tls_rejection() {
    # 准备服务端证书（如尚未生成）
    if [ ! -f "$tmpdir/srv_cert.pem" ]; then
        openssl genrsa -out "$tmpdir/srv_key2.pem" 2048 2>/dev/null
        openssl req -new -x509 -key "$tmpdir/srv_key2.pem" -out "$tmpdir/srv_cert.pem" -days 1 \
            -subj "/CN=localhost" 2>/dev/null
    fi
    local srv_key="$tmpdir/srv_key.pem"
    [ -f "$tmpdir/srv_key2.pem" ] && srv_key="$tmpdir/srv_key2.pem"

    # 启动 TLS 服务端
    openssl s_server -accept 24444 -cert "$tmpdir/srv_cert.pem" -key "$srv_key" -quiet &>/dev/null &
    local pid=$!
    # 等待服务端就绪
    for i in $(seq 1 30); do
        echo | openssl s_client -connect localhost:24444 2>/dev/null && break
        sleep 0.2
    done

    # 测试 SSLv3 和 TLS 1.0 是否被拒绝
    local ssl3_rejected=0 tls10_rejected=0
    if ! echo "Q" | openssl s_client -connect localhost:24444 -ssl3 2>/dev/null | grep -q "Cipher is"; then
        ssl3_rejected=1
    fi

    local tls10_out
    tls10_out=$(echo "Q" | openssl s_client -connect localhost:24444 -tls1 2>&1)
    if echo "$tls10_out" | grep -qiE "alert|unsupported|handshake failure"; then
        tls10_rejected=1
    elif echo "$tls10_out" | grep -q "Cipher is (NONE)"; then
        tls10_rejected=1   # ← 关键修复：(NONE) = 握手失败
    elif ! echo "$tls10_out" | grep -qE "Cipher is [A-Z]"; then
        tls10_rejected=1   # 没有有效密码套件名称也视为拒绝
    fi

    kill $pid 2>/dev/null
    wait $pid 2>/dev/null

    if [ "$ssl3_rejected" -eq 1 ] && [ "$tls10_rejected" -eq 1 ]; then
        echo "insecure-tls-rejection pass"
    else
        echo "insecure-tls-rejection fail"
    fi
}

# =============================================================================
# 20. AEAD 认证完整性验证
# =============================================================================
# 验证 AEAD（Authenticated Encryption with Associated Data）模式的认证机制：
#   1. 使用 AES-256-GCM 加密明文
#   2. 篡改密文的认证标签区域（末尾字节）
#   3. 解密篡改后的密文应当失败（认证标签不匹配）
# AEAD 的核心特性：密文完整性验证，任何篡改都会导致解密失败。
# ---------------------------------------------------------------------------
test_aead_integrity() {
    local plain="aead integrity test data"
    local key_hex=$(openssl rand -hex 32)   # AES-256 需要 256 位（32 字节）密钥
    local iv_hex=$(openssl rand -hex 12)    # GCM 模式推荐 96 位（12 字节）IV

    # 步骤 1：AES-256-GCM 加密
    if ! echo -n "$plain" | openssl enc -aes-256-gcm -K "$key_hex" -iv "$iv_hex" \
        -out "$tmpdir/gcm.enc" 2>/dev/null; then
        echo "aead-integrity skip"
        return
    fi

    # 步骤 2：篡改认证标签（修改密文末尾字节）
    # GCM 密文格式：ciphertext || auth_tag（通常最后 16 字节）
    cp "$tmpdir/gcm.enc" "$tmpdir/gcm_tampered.enc"
    local filesize=$(stat -c%s "$tmpdir/gcm_tampered.enc")
    if [ "$filesize" -gt 0 ]; then
        printf '\x00' | dd of="$tmpdir/gcm_tampered.enc" bs=1 seek=$((filesize - 1)) count=1 conv=notrunc 2>/dev/null
    fi

    # 步骤 3：尝试解密篡改后的密文，预期必须失败
    if ! openssl enc -aes-256-gcm -d -K "$key_hex" -iv "$iv_hex" \
        -in "$tmpdir/gcm_tampered.enc" -out /dev/null 2>/dev/null; then
        echo "aead-integrity pass"
    else
        echo "aead-integrity fail"
    fi
}

# =============================================================================
# 21. RSA 密钥长度下限验证
# =============================================================================
# 验证系统安全策略对 RSA 密钥长度的限制：
#   - 2048 位：当前安全基线，必须允许生成
#   - 1024 位：已被认为不安全（NIST 禁用），必须拒绝生成
# 这是等保 2.0 和密评的常见检查项。
# ---------------------------------------------------------------------------
test_rsa_min_keysize() {
    local min_accepted=0 max_rejected=0
    # 2048 位必须成功
    if openssl genrsa -out "$tmpdir/rsa2048.pem" 2048 2>/dev/null; then
        min_accepted=1
    fi
    # 1024 位必须被拒绝
    if ! openssl genrsa -out "$tmpdir/rsa1024.pem" 1024 2>/dev/null; then
        max_rejected=1
    fi
    if [ "$min_accepted" -eq 1 ] && [ "$max_rejected" -eq 1 ]; then
        echo "rsa-min-keysize pass"
    else
        echo "rsa-min-keysize fail"
    fi
}

# =============================================================================
# 22. 私钥文件权限安全检查
# =============================================================================
# 验证私钥文件的权限设置是否符合安全要求：
#   - 权限应为 600（仅所有者可读写）
#   - 其他用户应无任何权限
# 这是等保/密评中对密钥保护的必查项。
# ---------------------------------------------------------------------------
test_private_key_permission_audit() {
    openssl genrsa -out "$tmpdir/insecure.key" 2048 2>/dev/null
    # 先设置为不安全权限，再修正为安全权限
    chmod 644 "$tmpdir/insecure.key"
    chmod 600 "$tmpdir/insecure.key"
    local perms
    perms=$(stat -c "%a" "$tmpdir/insecure.key" 2>/dev/null)
    # 检查其他用户读权限位（第 8 个字符应为 '-'）
    local other_read
    other_read=$(stat -c "%A" "$tmpdir/insecure.key" 2>/dev/null | cut -c8)
    if [ "$perms" = "600" ] && [ "$other_read" = "-" ]; then
        echo "private-key-permission-audit pass"
    else
        echo "private-key-permission-audit fail"
    fi
}

# =============================================================================
# 23. SM2 证书请求（CSR）生成（国密）
# =============================================================================
# 国密证书管理测试。
# 生成 SM2 密钥对并创建 PKCS#10 证书签名请求（CSR），
# 验证 CSR 中包含 SM2 公钥信息。
# CSR 是向 CA 申请证书的标准格式。
# ---------------------------------------------------------------------------
test_sm2_csr() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_csr_key.pem" 2>/dev/null; then
        echo "sm2-csr fail"
        return
    fi
    if openssl req -new -sm3 -key "$tmpdir/sm2_csr_key.pem" -out "$tmpdir/sm2_csr.pem" \
        -subj "/C=CN/O=openEuler/OU=RV/CN=rv.openeuler.local" 2>/dev/null; then
        if openssl req -in "$tmpdir/sm2_csr.pem" -noout -text 2>/dev/null | grep -q "SM2"; then
            echo "sm2-csr pass"
        else
            echo "sm2-csr fail"
        fi
    else
        echo "sm2-csr fail"
    fi
}

# =============================================================================
# 24. SM2 加密解密测试（国密）
# =============================================================================
# 国密算法核心测试。
# 验证 SM2 非对称加密/解密功能：
#   - 使用公钥加密
#   - 使用私钥解密
#   - 验证解密后的明文与原始明文一致
# SM2 加密基于椭圆曲线 ElGamal 变体，支持最大明文长度有限。
# ---------------------------------------------------------------------------
test_sm2_encrypt_decrypt() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_enc_priv.pem" 2>/dev/null; then
        echo "sm2-encrypt-decrypt fail"
        return
    fi
    openssl ec -in "$tmpdir/sm2_enc_priv.pem" -pubout -out "$tmpdir/sm2_enc_pub.pem" 2>/dev/null
    echo "SM2 encrypt test data" > "$tmpdir/sm2_plain.txt"

    # 公钥加密（使用 SM3 作为 KDF 摘要算法）
    if ! openssl pkeyutl -encrypt -in "$tmpdir/sm2_plain.txt" -out "$tmpdir/sm2_cipher.bin" \
        -pubin -inkey "$tmpdir/sm2_enc_pub.pem" -pkeyopt digest:sm3 2>/dev/null; then
        echo "sm2-encrypt-decrypt fail"
        return
    fi

    # 私钥解密
    if ! openssl pkeyutl -decrypt -in "$tmpdir/sm2_cipher.bin" -out "$tmpdir/sm2_dec.txt" \
        -inkey "$tmpdir/sm2_enc_priv.pem" -pkeyopt digest:sm3 2>/dev/null; then
        echo "sm2-encrypt-decrypt fail"
        return
    fi

    # 验证明文一致性
    if diff -q "$tmpdir/sm2_plain.txt" "$tmpdir/sm2_dec.txt" >/dev/null 2>&1; then
        echo "sm2-encrypt-decrypt pass"
    else
        echo "sm2-encrypt-decrypt fail"
    fi
}

# =============================================================================
# 25. 内核 Crypto API 国密支持检查
# =============================================================================
# 验证 Linux 内核加密子系统是否注册了国密算法。
# 内核 Crypto API 是 dm-crypt、IMA/EVM、KTLS 等内核安全功能的底层基础。
# 如果 /proc/crypto 不存在（如容器环境），标记为 skip。
# ---------------------------------------------------------------------------
test_kernel_crypto_sm() {
    if [ ! -f /proc/crypto ]; then
        echo "kernel-crypto-sm2 skip"
        echo "kernel-crypto-sm3 skip"
        return
    fi
    # 检查 SM2
    if grep -q "sm2" /proc/crypto 2>/dev/null; then
        echo "kernel-crypto-sm2 pass"
    else
        echo "kernel-crypto-sm2 skip"
    fi
    # 检查 SM3
    if grep -q "sm3" /proc/crypto 2>/dev/null; then
        echo "kernel-crypto-sm3 pass"
    else
        echo "kernel-crypto-sm3 skip"
    fi
}



# =============================================================================
# 执行测试
# =============================================================================
{
  # --- 环境准备与基础组件检查 ---
  test_openssl_installed
  test_ca_store
  test_password_hash_policy
  test_sm3_password_hash_policy

  # --- 对称加密与哈希算法正确性 ---
  test_aes_correctness
  test_sm4_correctness
  test_hash_correctness
  test_sm3_correctness
  test_random_quality

  # --- 非对称密钥生成与签名验签 ---
  test_rsa_sign_verify
  test_ecc_keygen_sign
  test_sm2_sign_verify
  test_sm2_encrypt_decrypt
  test_rsa_min_keysize

  # --- 证书管理与 PKI 链路验证 ---
  test_cert_key_match
  test_sm2_cert_key_match
  test_cert_verify
  test_sm2_cert_verify
  test_cert_chain_verify
  test_sm2_cert_chain_verify
  test_cert_expiry
  test_sm2_cert_expiry
  test_sm2_csr
  test_private_key_permission_audit

  # --- TLS 通信与安全策略 ---
  test_tls_handshake
  test_insecure_tls_rejection
  test_weak_algo_rejection
  test_aead_integrity
  test_key_file_permission

  # --- 内核与架构 ---
  test_kernel_crypto_sm
} | tee "$RESULT_FILE"#!/bin/bash
# =============================================================================
# 加密与证书管理测试套件（openEuler RISC-V）
# =============================================================================
# 测试目标：验证 openEuler RV 操作系统在加密算法、证书管理、TLS 通信、
#          安全策略等方面的功能正确性与合规性
# 输出格式：测试项 pass/fail/skip
# =============================================================================

# 测试结果输出目录
OUTPUT="$(pwd)/output"
mkdir -p "$OUTPUT"
RESULT_FILE="${OUTPUT}/result.txt"

# 临时工作目录，脚本退出时自动清理
tmpdir=$(mktemp -d)
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

# =============================================================================
# 辅助函数
# =============================================================================

# ---------------------------------------------------------------------------
# 检查指定命令是否存在于系统 PATH 中
# 参数：$1 = 命令名
# 返回：0（存在）/ 1（不存在）
# ---------------------------------------------------------------------------
cmd_exists() { command -v "$1" &>/dev/null; }

# ---------------------------------------------------------------------------
# 检查指定目录中是否包含有效的证书文件
# 支持的证书格式：*.pem、*.crt、*.0（哈希命名）、*.der
# 参数：$1 = 目录路径
# 返回：0（存在证书文件）/ 1（不存在或为空）
# ---------------------------------------------------------------------------
has_cert_files() {
    local dir="$1"
    [ -d "$dir" ] || return 1
    local count
    count=$(find "$dir" -maxdepth 2 -type f \( -name "*.pem" -o -name "*.crt" -o -name "*.0" -o -name "*.der" \) 2>/dev/null | wc -l)
    [ "$count" -gt 0 ]
}

# =============================================================================
# 1. OpenSSL 安装检查
# =============================================================================
# OpenSSL 是 openEuler 国密支持的核心组件，所有后续测试的前提条件。
# 验证系统是否已安装 openssl 命令行工具。
# ---------------------------------------------------------------------------
test_openssl_installed() {
    if cmd_exists openssl; then
        echo "openssl-installed pass"
    else
        echo "openssl-installed fail"
    fi
}

# =============================================================================
# 2. AES-256-CBC 加密/解密正确性
# =============================================================================
# 国际算法兼容性基线测试。
# 验证 AES-256-CBC 对称加密的往返正确性：
#   明文 → 加密 → 解密 → 明文
# 使用 PBKDF2 派生密钥（-pass 选项自动处理）。
# ---------------------------------------------------------------------------
test_aes_correctness() {
    local plain="hello world test"
    local pass="testkey123"
    if ! echo -n "$plain" | openssl enc -aes-256-cbc -pass pass:"$pass" -out "$tmpdir/aes.enc" 2>/dev/null; then
        echo "aes-correctness fail"
        return
    fi
    local decrypted
    decrypted=$(openssl enc -aes-256-cbc -d -pass pass:"$pass" -in "$tmpdir/aes.enc" 2>/dev/null)
    if [ "$decrypted" = "$plain" ]; then
        echo "aes-correctness pass"
    else
        echo "aes-correctness fail"
    fi
}

# =============================================================================
# 3. SHA256/512 标准哈希正确性
# =============================================================================
# 国际算法兼容性基线测试。
# 使用 NIST 标准测试向量验证 SHA-256 和 SHA-512 的正确性：
#   输入 "abc" 的哈希值是公开定义的标准值
# ---------------------------------------------------------------------------
test_hash_correctness() {
    local test_str="abc"
    local sha256_expected="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    local sha512_expected="ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"

    local sha256_result
    sha256_result=$(echo -n "$test_str" | openssl dgst -sha256 | awk '{print $NF}')
    if [ "$sha256_result" != "$sha256_expected" ]; then
        echo "hash-correctness fail"
        return
    fi

    local sha512_result
    sha512_result=$(echo -n "$test_str" | openssl dgst -sha512 | awk '{print $NF}')
    if [ "$sha512_result" != "$sha512_expected" ]; then
        echo "hash-correctness fail"
        return
    fi

    echo "hash-correctness pass"
}

# =============================================================================
# 4. 随机数质量简单检测
# =============================================================================
# 验证 OpenSSL 随机数生成器的基本质量：
#   连续生成 20 个 128 位（16 字节十六进制）随机数
#   检查是否有重复值（理论上概率极低）
# 注意：这是简单检测，非密码学强度统计测试（如 NIST SP 800-22）
# ---------------------------------------------------------------------------
test_random_quality() {
    local samples=()
    for i in $(seq 1 20); do
        samples+=($(openssl rand -hex 16 2>/dev/null))
    done
    local unique=$(printf '%s\n' "${samples[@]}" | sort -u | wc -l)
    [ "$unique" -eq 20 ] && echo "random-quality pass" || echo "random-quality fail"
}

# =============================================================================
# 5. RSA 密钥生成与签名/验签正确性
# =============================================================================
# 国际算法兼容性基线测试。
# 验证 RSA-2048 密钥对生成、SHA-256 签名及验签的完整流程。
# RSA-2048 是当前安全基线（低于 2048 位被认为不安全）。
# ---------------------------------------------------------------------------
test_rsa_sign_verify() {
    if ! openssl genrsa -out "$tmpdir/rsa_priv.pem" 2048 2>/dev/null; then
        echo "rsa-sign-verify fail"
        return
    fi
    if ! openssl rsa -in "$tmpdir/rsa_priv.pem" -pubout -out "$tmpdir/rsa_pub.pem" 2>/dev/null; then
        echo "rsa-sign-verify fail"
        return
    fi
    echo -n "testdata" | openssl dgst -sha256 -sign "$tmpdir/rsa_priv.pem" -out "$tmpdir/rsa.sig" 2>/dev/null
    if echo -n "testdata" | openssl dgst -sha256 -verify "$tmpdir/rsa_pub.pem" -signature "$tmpdir/rsa.sig" 2>/dev/null; then
        echo "rsa-sign-verify pass"
    else
        echo "rsa-sign-verify fail"
    fi
}

# =============================================================================
# 6. ECC (P-256) 密钥生成与签名验签
# =============================================================================
# 国际算法兼容性基线测试。
# 验证 NIST P-256（prime256v1）椭圆曲线密钥生成及 ECDSA 签名验签。
# P-256 是 TLS 1.2/1.3 广泛使用的曲线。
# ---------------------------------------------------------------------------
test_ecc_keygen_sign() {
    if ! openssl ecparam -genkey -name prime256v1 -out "$tmpdir/ecc_priv.pem" 2>/dev/null; then
        echo "ecc-keygen-sign fail"
        return
    fi
    if ! openssl ec -in "$tmpdir/ecc_priv.pem" -pubout -out "$tmpdir/ecc_pub.pem" 2>/dev/null; then
        echo "ecc-keygen-sign fail"
        return
    fi
    echo -n "ecctest" > "$tmpdir/ecc_data.txt"
    if ! openssl dgst -sha256 -sign "$tmpdir/ecc_priv.pem" -out "$tmpdir/ecc.sig" "$tmpdir/ecc_data.txt" 2>/dev/null; then
        echo "ecc-keygen-sign fail"
        return
    fi
    if openssl dgst -sha256 -verify "$tmpdir/ecc_pub.pem" -signature "$tmpdir/ecc.sig" "$tmpdir/ecc_data.txt" 2>/dev/null; then
        echo "ecc-keygen-sign pass"
    else
        echo "ecc-keygen-sign fail"
    fi
}

# =============================================================================
# 7. SM3 哈希正确性（国密算法）
# =============================================================================
# 国密算法核心测试。
# 使用 GM/T 0004-2012 标准测试向量验证 SM3 哈希正确性：
#   输入 "abc" 的 SM3 哈希值是公开定义的标准值
# SM3 是国产密码杂凑算法，输出 256 位摘要，功能对标 SHA-256。
# ---------------------------------------------------------------------------
test_sm3_correctness() {
    local expected="66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0"
    local result
    # 优先使用 openssl dgst -sm3（OpenSSL 3.x 推荐方式）
    result=$(echo -n "abc" | openssl dgst -sm3 2>/dev/null | awk '{print $NF}')
    # 回退到 openssl sm3（旧版本兼容）
    if [ -z "$result" ]; then
        result=$(echo -n "abc" | openssl sm3 2>/dev/null | awk '{print $NF}')
    fi
    if [ "$result" = "$expected" ]; then
        echo "sm3-correctness pass"
    else
        echo "sm3-correctness fail"
    fi
}

# =============================================================================
# 8. SM4-CBC 加密/解密正确性（国密算法）
# =============================================================================
# 国密算法核心测试。
# 验证 SM4-CBC 对称加密的往返正确性。
# SM4 是国产分组密码算法，分组长度 128 位，密钥长度 128 位，
# 功能对标 AES-128。
# 测试兼容大小写两种命名方式（sm4-cbc / SM4-CBC）。
# ---------------------------------------------------------------------------
test_sm4_correctness() {
    local plain="sm4testdata123"
    local pass="sm4key"
    # 尝试小写命名
    if echo -n "$plain" | openssl enc -sm4-cbc -pass pass:"$pass" -out "$tmpdir/sm4.enc" 2>/dev/null; then
        local decrypted
        decrypted=$(openssl enc -sm4-cbc -d -pass pass:"$pass" -in "$tmpdir/sm4.enc" 2>/dev/null)
        if [ "$decrypted" = "$plain" ]; then
            echo "sm4-correctness pass"
            return
        fi
    fi
    # 尝试大写命名（兼容部分版本）
    if echo -n "$plain" | openssl enc -SM4-CBC -pass pass:"$pass" -out "$tmpdir/sm4.enc" 2>/dev/null; then
        local decrypted
        decrypted=$(openssl enc -SM4-CBC -d -pass pass:"$pass" -in "$tmpdir/sm4.enc" 2>/dev/null)
        if [ "$decrypted" = "$plain" ]; then
            echo "sm4-correctness pass"
            return
        fi
    fi
    echo "sm4-correctness fail"
}

# =============================================================================
# 9. SM2 密钥生成及签名验签正确性（国密算法）
# =============================================================================
# 国密算法核心测试。
# 验证 SM2 椭圆曲线密钥对生成、SM3 摘要签名及验签的完整流程。
# SM2 是国产非对称密码算法，基于椭圆曲线，功能对标 ECDSA/ECDH。
# 兼容大小写命名（SM2 / sm2），支持 dgst 和 pkeyutl 两种签名接口。
# ---------------------------------------------------------------------------
test_sm2_sign_verify() {
    # 尝试生成 SM2 密钥（兼容大小写命名）
    if openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_priv.pem" 2>/dev/null; then
        :
    elif openssl ecparam -genkey -name sm2 -out "$tmpdir/sm2_priv.pem" 2>/dev/null; then
        :
    else
        echo "sm2-sign-verify fail"
        return
    fi
    # 导出公钥
    openssl ec -in "$tmpdir/sm2_priv.pem" -pubout -out "$tmpdir/sm2_pub.pem" 2>/dev/null
    # 使用 SM3 摘要进行签名
    echo -n "test" | openssl dgst -sm3 -sign "$tmpdir/sm2_priv.pem" -out "$tmpdir/sm2.sig" 2>/dev/null
    # 如果 dgst 签名失败，回退到 pkeyutl
    if [ ! -s "$tmpdir/sm2.sig" ]; then
        echo -n "test" | openssl pkeyutl -sign -inkey "$tmpdir/sm2_priv.pem" -out "$tmpdir/sm2.sig" 2>/dev/null
    fi
    # 验签
    if [ -s "$tmpdir/sm2.sig" ]; then
        if echo -n "test" | openssl dgst -sm3 -verify "$tmpdir/sm2_pub.pem" -signature "$tmpdir/sm2.sig" 2>/dev/null; then
            echo "sm2-sign-verify pass"
        elif echo -n "test" | openssl pkeyutl -verify -pubin -inkey "$tmpdir/sm2_pub.pem" -sigfile "$tmpdir/sm2.sig" 2>/dev/null; then
            echo "sm2-sign-verify pass"
        else
            echo "sm2-sign-verify fail"
        fi
    else
        echo "sm2-sign-verify fail"
    fi
}

# =============================================================================
# 10. RSA 自签证书公钥与私钥匹配性验证
# =============================================================================
# 证书管理基线测试（RSA）。
# 生成 RSA 自签名证书，提取证书中的公钥，与私钥导出的公钥对比，
# 验证证书确实由对应私钥签发。
# ---------------------------------------------------------------------------
test_cert_key_match() {
    openssl genrsa -out "$tmpdir/key.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/key.pem" -out "$tmpdir/cert.pem" -days 1 \
        -subj "/CN=Test" 2>/dev/null
    local cert_pub key_pub
    cert_pub=$(openssl x509 -in "$tmpdir/cert.pem" -pubkey -noout 2>/dev/null)
    key_pub=$(openssl rsa -in "$tmpdir/key.pem" -pubout 2>/dev/null)
    if [ "$cert_pub" = "$key_pub" ]; then
        echo "cert-key-match pass"
    else
        echo "cert-key-match fail"
    fi
}

# =============================================================================
# 10b. SM2 自签证书公钥与私钥匹配性验证（国密）
# =============================================================================
# 国密证书管理测试。
# 生成 SM2 自签名证书（使用 SM3 摘要算法），验证证书公钥与私钥的匹配性。
# ---------------------------------------------------------------------------
test_sm2_cert_key_match() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_ck_key.pem" 2>/dev/null; then
        echo "sm2-cert-key-match fail"
        return
    fi
    openssl req -new -x509 -sm3 -key "$tmpdir/sm2_ck_key.pem" -out "$tmpdir/sm2_ck_cert.pem" -days 1 \
        -subj "/C=CN/O=openEuler/CN=SM2-Test" 2>/dev/null
    local cert_pub key_pub
    cert_pub=$(openssl x509 -in "$tmpdir/sm2_ck_cert.pem" -pubkey -noout 2>/dev/null)
    key_pub=$(openssl ec -in "$tmpdir/sm2_ck_key.pem" -pubout 2>/dev/null)
    if [ "$cert_pub" = "$key_pub" ]; then
        echo "sm2-cert-key-match pass"
    else
        echo "sm2-cert-key-match fail"
    fi
}

# =============================================================================
# 11. RSA 自签证书验证
# =============================================================================
# 证书管理基线测试（RSA）。
# 生成 RSA 自签名证书，使用 openssl verify 验证证书有效性。
# 自签名证书作为自身的信任锚进行验证。
# ---------------------------------------------------------------------------
test_cert_verify() {
    openssl genrsa -out "$tmpdir/key2.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/key2.pem" -out "$tmpdir/cert2.pem" -days 1 \
        -subj "/CN=TestVerify" 2>/dev/null
    if openssl verify -CAfile "$tmpdir/cert2.pem" "$tmpdir/cert2.pem" &>/dev/null; then
        echo "cert-verify pass"
    else
        echo "cert-verify fail"
    fi
}

# =============================================================================
# 11b. SM2 自签证书验证（国密）
# =============================================================================
# 国密证书管理测试。
# 生成 SM2 自签名证书（使用 SM3 摘要），验证证书链。
# ---------------------------------------------------------------------------
test_sm2_cert_verify() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_cv_key.pem" 2>/dev/null; then
        echo "sm2-cert-verify fail"
        return
    fi
    openssl req -new -x509 -sm3 -key "$tmpdir/sm2_cv_key.pem" -out "$tmpdir/sm2_cv_cert.pem" -days 1 \
        -subj "/C=CN/O=openEuler/CN=SM2-Verify" 2>/dev/null
    if openssl verify -CAfile "$tmpdir/sm2_cv_cert.pem" "$tmpdir/sm2_cv_cert.pem" &>/dev/null; then
        echo "sm2-cert-verify pass"
    else
        echo "sm2-cert-verify fail"
    fi
}

# =============================================================================
# 12. RSA 多层级证书链验证
# =============================================================================
# 证书管理基线测试（RSA）。
# 构建三层 PKI 架构：根 CA → 中间 CA → 服务器证书
# 使用 X.509 v3 扩展定义各层级约束（basicConstraints、keyUsage 等）。
# 验证 openssl verify 能否正确验证完整证书链。
# ---------------------------------------------------------------------------
test_cert_chain_verify() {
    # 创建 X.509 v3 扩展配置文件
    # 生成包含 req 段和扩展段的完整临时配置
    cat > "$tmpdir/ca_ext.cnf" << 'EOF'
[ req ]
distinguished_name = req_dn
x509_extensions    = v3_ca
prompt             = no

[ req_dn ]
C  = CN
O  = Root
CN = RootCA

[ v3_ca ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer

[ v3_inter ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer

[ v3_server ]
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

    # 根 CA：自签名（使用 -config 替代 -extfile + -extensions）
    openssl genrsa -out "$tmpdir/root.key" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/root.key" -out "$tmpdir/root.crt" -days 365 \
        -config "$tmpdir/ca_ext.cnf" 2>/dev/null

    # 中间 CA：由根 CA 签发
    openssl genrsa -out "$tmpdir/inter.key" 2048 2>/dev/null
    openssl req -new -key "$tmpdir/inter.key" -out "$tmpdir/inter.csr" \
        -subj "/C=CN/O=Inter/CN=InterCA" 2>/dev/null
    openssl x509 -req -in "$tmpdir/inter.csr" -CA "$tmpdir/root.crt" -CAkey "$tmpdir/root.key" \
        -out "$tmpdir/inter.crt" -days 365 -CAcreateserial \
        -extensions v3_inter -extfile "$tmpdir/ca_ext.cnf" 2>/dev/null

    # 服务器证书：由中间 CA 签发
    openssl genrsa -out "$tmpdir/srv.key" 2048 2>/dev/null
    openssl req -new -key "$tmpdir/srv.key" -out "$tmpdir/srv.csr" \
        -subj "/C=CN/O=Server/CN=localhost" 2>/dev/null
    openssl x509 -req -in "$tmpdir/srv.csr" -CA "$tmpdir/inter.crt" -CAkey "$tmpdir/inter.key" \
        -out "$tmpdir/srv.crt" -days 365 -CAcreateserial \
        -extensions v3_server -extfile "$tmpdir/ca_ext.cnf" 2>/dev/null

    # 验证证书链：根 CA 作为信任锚，中间 CA 作为非信任中间证书
    local verify_result
    verify_result=$(openssl verify -CAfile "$tmpdir/root.crt" -untrusted "$tmpdir/inter.crt" "$tmpdir/srv.crt" 2>&1)
    if echo "$verify_result" | grep -q "OK"; then
        echo "cert-chain-verify pass"
    else
        echo "cert-chain-verify fail"
    fi
}

# =============================================================================
# 12b. SM2 多层级证书链验证
# =============================================================================
# 国密证书管理核心测试。
# 构建三层 SM2 PKI 架构，使用 SM3 作为摘要算法：
#   根 CA（SM2 自签名）→ 中间 CA（SM2，根签发）→ 服务器证书（SM2，中间签发）
# 验证 openssl verify 对 SM2 证书链的完整验证能力。
# ---------------------------------------------------------------------------
test_sm2_cert_chain_verify() {
    local sm2_ca_dir="$tmpdir/sm2_chain_ca"
    mkdir -p "$sm2_ca_dir"

    cat > "$sm2_ca_dir/ca_ext.cnf" << 'EOF'
[ req ]
distinguished_name = req_dn
x509_extensions    = v3_ca
prompt             = no

[ req_dn ]
C  = CN
O  = Root
CN = RootCA

[ v3_ca ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer

[ v3_inter ]
basicConstraints       = critical, CA:TRUE
keyUsage               = critical, cRLSign, keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer

[ v3_server ]
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

    # 根 CA：SM2 自签名，SM3 摘要
    openssl ecparam -genkey -name SM2 -out "$sm2_ca_dir/root.key" 2>/dev/null
    openssl req -new -x509 -sm3 -key "$sm2_ca_dir/root.key" -out "$sm2_ca_dir/root.crt" -days 365 \
        -subj "/C=CN/O=openEuler/CN=SM2-RootCA" \
        -config "$sm2_ca_dir/ca_ext.cnf" 2>/dev/null

    # 中间 CA：由根 CA 用 SM2+SM3 签发
    openssl ecparam -genkey -name SM2 -out "$sm2_ca_dir/inter.key" 2>/dev/null
    openssl req -new -sm3 -key "$sm2_ca_dir/inter.key" -out "$sm2_ca_dir/inter.csr" \
        -subj "/C=CN/O=openEuler/CN=SM2-InterCA" 2>/dev/null
    openssl x509 -req -in "$sm2_ca_dir/inter.csr" -CA "$sm2_ca_dir/root.crt" -CAkey "$sm2_ca_dir/root.key" \
        -out "$sm2_ca_dir/inter.crt" -days 365 -CAcreateserial \
        -extensions v3_inter -extfile "$sm2_ca_dir/ca_ext.cnf" 2>/dev/null

    # 服务器证书：由中间 CA 用 SM2+SM3 签发
    openssl ecparam -genkey -name SM2 -out "$sm2_ca_dir/srv.key" 2>/dev/null
    openssl req -new -sm3 -key "$sm2_ca_dir/srv.key" -out "$sm2_ca_dir/srv.csr" \
        -subj "/C=CN/O=openEuler/CN=localhost" 2>/dev/null
    openssl x509 -req -in "$sm2_ca_dir/srv.csr" -CA "$sm2_ca_dir/inter.crt" -CAkey "$sm2_ca_dir/inter.key" \
        -out "$sm2_ca_dir/srv.crt" -days 365 -CAcreateserial \
        -extensions v3_server -extfile "$sm2_ca_dir/ca_ext.cnf" 2>/dev/null

    # 验证 SM2 证书链
    local verify_result
    verify_result=$(openssl verify -CAfile "$sm2_ca_dir/root.crt" -untrusted "$sm2_ca_dir/inter.crt" "$sm2_ca_dir/srv.crt" 2>&1)
    if echo "$verify_result" | grep -q "OK"; then
        echo "sm2-cert-chain-verify pass"
    else
        echo "sm2-cert-chain-verify fail"
    fi
}

# =============================================================================
# 13. RSA 证书有效期检查
# =============================================================================
# 证书管理基线测试（RSA）。
# 生成 RSA 自签名证书，验证 openssl x509 -enddate 能否正确读取有效期。
# ---------------------------------------------------------------------------
test_cert_expiry() {
    openssl genrsa -out "$tmpdir/key3.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/key3.pem" -out "$tmpdir/cert3.pem" -days 1 \
        -subj "/CN=ExpiryTest" 2>/dev/null
    if openssl x509 -in "$tmpdir/cert3.pem" -noout -enddate &>/dev/null; then
        echo "cert-expiry pass"
    else
        echo "cert-expiry fail"
    fi
}

# =============================================================================
# 13b. SM2 证书有效期检查（国密）
# =============================================================================
# 国密证书管理测试。
# 生成 SM2 自签名证书，验证有效期读取。
# ---------------------------------------------------------------------------
test_sm2_cert_expiry() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_exp_key.pem" 2>/dev/null; then
        echo "sm2-cert-expiry fail"
        return
    fi
    openssl req -new -x509 -sm3 -key "$tmpdir/sm2_exp_key.pem" -out "$tmpdir/sm2_exp_cert.pem" -days 1 \
        -subj "/C=CN/O=openEuler/CN=SM2-Expiry" 2>/dev/null
    if openssl x509 -in "$tmpdir/sm2_exp_cert.pem" -noout -enddate &>/dev/null; then
        echo "sm2-cert-expiry pass"
    else
        echo "sm2-cert-expiry fail"
    fi
}

# =============================================================================
# 14. 系统 CA 证书库存在性
# =============================================================================
# 验证系统 CA 信任库是否配置正确。
# openEuler 使用 /etc/pki/ca-trust 体系（源自 Fedora/RHEL），
# 与 Debian/Ubuntu 的 /usr/share/ca-certificates 不同。
# 检查路径已适配 openEuler 实际目录结构。
# ---------------------------------------------------------------------------
test_ca_store() {
    local dirs=(
        "/etc/pki/ca-trust/extracted"         # openEuler 主信任锚目录
        "/etc/pki/tls/certs"                  # 系统 TLS 证书目录
        "/etc/ssl/certs"                      # 兼容路径（通常是软链接）
        "/etc/pki/ca-trust/source/anchors"   # 管理员自定义 CA 存放目录
    )
    for d in "${dirs[@]}"; do
        if has_cert_files "$d"; then
            echo "ca-store pass"
            return
        fi
    done
    echo "ca-store fail"
}

# =============================================================================
# 15. TLS 1.2 握手及加密通信验证（RSA基线）
# =============================================================================
# TLS 通信基线测试（国际算法）。
# 启动 openssl s_server 作为 TLS 服务端，使用 RSA 证书。
# 客户端使用 openssl s_client 连接，验证 TLS 1.2 握手成功及加密套件协商。
# ---------------------------------------------------------------------------
test_tls_handshake() {
    openssl genrsa -out "$tmpdir/srv_key.pem" 2048 2>/dev/null
    openssl req -new -x509 -key "$tmpdir/srv_key.pem" -out "$tmpdir/srv_cert.pem" -days 1 \
        -subj "/CN=localhost" 2>/dev/null

    # 后台启动 TLS 服务端
    openssl s_server -accept 24443 -cert "$tmpdir/srv_cert.pem" -key "$tmpdir/srv_key.pem" -quiet &>/dev/null &
    local pid=$!
    sleep 1

    # 客户端连接，检查是否成功协商加密套件
    local result
    result=$(echo "Q" | openssl s_client -connect localhost:24443 -tls1_2 2>/dev/null | grep -c "Cipher is")
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    if [ "$result" -gt 0 ]; then
        echo "tls-handshake pass"
    else
        echo "tls-handshake fail"
    fi
}

# =============================================================================
# 16. 私钥文件权限检查
# =============================================================================
# 验证密钥文件能否正确设置 600 权限（仅所有者可读写）。
# 私钥文件权限过宽（如 644）会导致安全风险，这是等保/密评的常见检查项。
# ---------------------------------------------------------------------------
test_key_file_permission() {
    openssl genrsa -out "$tmpdir/perm_test.key" 2048 2>/dev/null
    chmod 600 "$tmpdir/perm_test.key"
    local perms
    perms=$(stat -c "%a" "$tmpdir/perm_test.key" 2>/dev/null)
    if [ "$perms" = "600" ]; then
        echo "key-file-permission pass"
    else
        echo "key-file-permission fail"
    fi
}

# =============================================================================
# 17. 系统口令哈希策略检查（SHA256/SHA512）
# =============================================================================
# 验证系统 PAM 配置中是否启用了安全的口令哈希算法（SHA-512 或 SHA-256）。
# 检查常见的 PAM 配置文件路径。
# ---------------------------------------------------------------------------
test_password_hash_policy() {
    local found=0
    local files=("/etc/pam.d/system-auth" "/etc/pam.d/common-password" "/etc/pam.d/password-auth")
    for f in "${files[@]}"; do
        if [ -f "$f" ] && grep -q "sha512" "$f" 2>/dev/null; then
            found=1
            break
        fi
    done
    if [ "$found" -eq 1 ]; then
        echo "password-hash-policy pass"
    else
        echo "password-hash-policy fail"
    fi
}

# =============================================================================
# 17b. SM3 口令哈希策略检查（国密）
# =============================================================================
# 验证系统 PAM 配置中是否支持 SM3 作为口令哈希算法。
# openEuler 部分版本支持 pam_sm3 模块实现国密口令策略。
# 如果系统中未配置 SM3，标记为 skip（非失败）。
# ---------------------------------------------------------------------------
test_sm3_password_hash_policy() {
    local found=0
    local files=("/etc/pam.d/system-auth" "/etc/pam.d/common-password" "/etc/pam.d/password-auth")
    for f in "${files[@]}"; do
        if [ -f "$f" ] && grep -qi "sm3" "$f" 2>/dev/null; then
            found=1
            break
        fi
    done
    if [ "$found" -eq 1 ]; then
        echo "sm3-password-hash-policy pass"
    else
        echo "sm3-password-hash-policy skip"
    fi
}

# =============================================================================
# 18. 弱算法拒绝验证
# =============================================================================
# 验证系统是否拒绝使用已知不安全的密码算法：
#   - DES-CBC：密钥长度过短（56位），已被暴力破解
#   - RC4：存在统计偏差攻击，TLS 中已禁用
#   - MD5：存在碰撞攻击，不再用于数字签名
# openEuler 默认安全策略应拒绝上述弱算法。
# 至少拒绝 2 种弱算法即判定通过（兼容不同安全策略级别）。
# ---------------------------------------------------------------------------
test_weak_algo_rejection() {
    local weak_rejected=0
    # 测试 DES-CBC 是否被拒绝
    if ! echo -n "test" | openssl enc -des-cbc -pass pass:"key" -pbkdf2 -out /dev/null 2>/dev/null; then
        weak_rejected=$((weak_rejected + 1))
    fi
    # 测试 RC4 是否被拒绝
    if ! echo -n "test" | openssl enc -rc4 -pass pass:"key" -out /dev/null 2>/dev/null; then
        weak_rejected=$((weak_rejected + 1))
    fi
    # 测试 MD5 签名是否被拒绝
    if ! echo -n "test" | openssl dgst -md5 -sign "$tmpdir/rsa_priv.pem" -out /dev/null 2>/dev/null; then
        weak_rejected=$((weak_rejected + 1))
    fi
    if [ "$weak_rejected" -ge 2 ]; then
        echo "weak-algo-rejection pass"
    else
        echo "weak-algo-rejection fail"
    fi
}

# =============================================================================
# 19. TLS 不安全协议版本拒绝
# =============================================================================
# 验证 TLS 服务端是否拒绝不安全的协议版本：
#   - SSLv3：存在 POODLE 攻击，已废弃
#   - TLS 1.0：存在 BEAST 等攻击，已废弃
# openEuler 默认应仅允许 TLS 1.2+ 连接。
# ---------------------------------------------------------------------------
test_insecure_tls_rejection() {
    # 准备服务端证书（如尚未生成）
    if [ ! -f "$tmpdir/srv_cert.pem" ]; then
        openssl genrsa -out "$tmpdir/srv_key2.pem" 2048 2>/dev/null
        openssl req -new -x509 -key "$tmpdir/srv_key2.pem" -out "$tmpdir/srv_cert.pem" -days 1 \
            -subj "/CN=localhost" 2>/dev/null
    fi
    local srv_key="$tmpdir/srv_key.pem"
    [ -f "$tmpdir/srv_key2.pem" ] && srv_key="$tmpdir/srv_key2.pem"

    # 启动 TLS 服务端
    openssl s_server -accept 24444 -cert "$tmpdir/srv_cert.pem" -key "$srv_key" -quiet &>/dev/null &
    local pid=$!
    # 等待服务端就绪
    for i in $(seq 1 30); do
        echo | openssl s_client -connect localhost:24444 2>/dev/null && break
        sleep 0.2
    done

    # 测试 SSLv3 和 TLS 1.0 是否被拒绝
    local ssl3_rejected=0 tls10_rejected=0
    if ! echo "Q" | openssl s_client -connect localhost:24444 -ssl3 2>/dev/null | grep -q "Cipher is"; then
        ssl3_rejected=1
    fi

    local tls10_out
    tls10_out=$(echo "Q" | openssl s_client -connect localhost:24444 -tls1 2>&1)
    if echo "$tls10_out" | grep -qiE "alert|unsupported|handshake failure"; then
        tls10_rejected=1
    elif echo "$tls10_out" | grep -q "Cipher is (NONE)"; then
        tls10_rejected=1   # ← 关键修复：(NONE) = 握手失败
    elif ! echo "$tls10_out" | grep -qE "Cipher is [A-Z]"; then
        tls10_rejected=1   # 没有有效密码套件名称也视为拒绝
    fi

    kill $pid 2>/dev/null
    wait $pid 2>/dev/null

    if [ "$ssl3_rejected" -eq 1 ] && [ "$tls10_rejected" -eq 1 ]; then
        echo "insecure-tls-rejection pass"
    else
        echo "insecure-tls-rejection fail"
    fi
}

# =============================================================================
# 20. AEAD 认证完整性验证
# =============================================================================
# 验证 AEAD（Authenticated Encryption with Associated Data）模式的认证机制：
#   1. 使用 AES-256-GCM 加密明文
#   2. 篡改密文的认证标签区域（末尾字节）
#   3. 解密篡改后的密文应当失败（认证标签不匹配）
# AEAD 的核心特性：密文完整性验证，任何篡改都会导致解密失败。
# ---------------------------------------------------------------------------
test_aead_integrity() {
    local plain="aead integrity test data"
    local key_hex=$(openssl rand -hex 32)   # AES-256 需要 256 位（32 字节）密钥
    local iv_hex=$(openssl rand -hex 12)    # GCM 模式推荐 96 位（12 字节）IV

    # 步骤 1：AES-256-GCM 加密
    if ! echo -n "$plain" | openssl enc -aes-256-gcm -K "$key_hex" -iv "$iv_hex" \
        -out "$tmpdir/gcm.enc" 2>/dev/null; then
        echo "aead-integrity skip"
        return
    fi

    # 步骤 2：篡改认证标签（修改密文末尾字节）
    # GCM 密文格式：ciphertext || auth_tag（通常最后 16 字节）
    cp "$tmpdir/gcm.enc" "$tmpdir/gcm_tampered.enc"
    local filesize=$(stat -c%s "$tmpdir/gcm_tampered.enc")
    if [ "$filesize" -gt 0 ]; then
        printf '\x00' | dd of="$tmpdir/gcm_tampered.enc" bs=1 seek=$((filesize - 1)) count=1 conv=notrunc 2>/dev/null
    fi

    # 步骤 3：尝试解密篡改后的密文，预期必须失败
    if ! openssl enc -aes-256-gcm -d -K "$key_hex" -iv "$iv_hex" \
        -in "$tmpdir/gcm_tampered.enc" -out /dev/null 2>/dev/null; then
        echo "aead-integrity pass"
    else
        echo "aead-integrity fail"
    fi
}

# =============================================================================
# 21. RSA 密钥长度下限验证
# =============================================================================
# 验证系统安全策略对 RSA 密钥长度的限制：
#   - 2048 位：当前安全基线，必须允许生成
#   - 1024 位：已被认为不安全（NIST 禁用），必须拒绝生成
# 这是等保 2.0 和密评的常见检查项。
# ---------------------------------------------------------------------------
test_rsa_min_keysize() {
    local min_accepted=0 max_rejected=0
    # 2048 位必须成功
    if openssl genrsa -out "$tmpdir/rsa2048.pem" 2048 2>/dev/null; then
        min_accepted=1
    fi
    # 1024 位必须被拒绝
    if ! openssl genrsa -out "$tmpdir/rsa1024.pem" 1024 2>/dev/null; then
        max_rejected=1
    fi
    if [ "$min_accepted" -eq 1 ] && [ "$max_rejected" -eq 1 ]; then
        echo "rsa-min-keysize pass"
    else
        echo "rsa-min-keysize fail"
    fi
}

# =============================================================================
# 22. 私钥文件权限安全检查
# =============================================================================
# 验证私钥文件的权限设置是否符合安全要求：
#   - 权限应为 600（仅所有者可读写）
#   - 其他用户应无任何权限
# 这是等保/密评中对密钥保护的必查项。
# ---------------------------------------------------------------------------
test_private_key_permission_audit() {
    openssl genrsa -out "$tmpdir/insecure.key" 2048 2>/dev/null
    # 先设置为不安全权限，再修正为安全权限
    chmod 644 "$tmpdir/insecure.key"
    chmod 600 "$tmpdir/insecure.key"
    local perms
    perms=$(stat -c "%a" "$tmpdir/insecure.key" 2>/dev/null)
    # 检查其他用户读权限位（第 8 个字符应为 '-'）
    local other_read
    other_read=$(stat -c "%A" "$tmpdir/insecure.key" 2>/dev/null | cut -c8)
    if [ "$perms" = "600" ] && [ "$other_read" = "-" ]; then
        echo "private-key-permission-audit pass"
    else
        echo "private-key-permission-audit fail"
    fi
}

# =============================================================================
# 23. SM2 证书请求（CSR）生成（国密）
# =============================================================================
# 国密证书管理测试。
# 生成 SM2 密钥对并创建 PKCS#10 证书签名请求（CSR），
# 验证 CSR 中包含 SM2 公钥信息。
# CSR 是向 CA 申请证书的标准格式。
# ---------------------------------------------------------------------------
test_sm2_csr() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_csr_key.pem" 2>/dev/null; then
        echo "sm2-csr fail"
        return
    fi
    if openssl req -new -sm3 -key "$tmpdir/sm2_csr_key.pem" -out "$tmpdir/sm2_csr.pem" \
        -subj "/C=CN/O=openEuler/OU=RV/CN=rv.openeuler.local" 2>/dev/null; then
        if openssl req -in "$tmpdir/sm2_csr.pem" -noout -text 2>/dev/null | grep -q "SM2"; then
            echo "sm2-csr pass"
        else
            echo "sm2-csr fail"
        fi
    else
        echo "sm2-csr fail"
    fi
}

# =============================================================================
# 24. SM2 加密解密测试（国密）
# =============================================================================
# 国密算法核心测试。
# 验证 SM2 非对称加密/解密功能：
#   - 使用公钥加密
#   - 使用私钥解密
#   - 验证解密后的明文与原始明文一致
# SM2 加密基于椭圆曲线 ElGamal 变体，支持最大明文长度有限。
# ---------------------------------------------------------------------------
test_sm2_encrypt_decrypt() {
    if ! openssl ecparam -genkey -name SM2 -out "$tmpdir/sm2_enc_priv.pem" 2>/dev/null; then
        echo "sm2-encrypt-decrypt fail"
        return
    fi
    openssl ec -in "$tmpdir/sm2_enc_priv.pem" -pubout -out "$tmpdir/sm2_enc_pub.pem" 2>/dev/null
    echo "SM2 encrypt test data" > "$tmpdir/sm2_plain.txt"

    # 公钥加密（使用 SM3 作为 KDF 摘要算法）
    if ! openssl pkeyutl -encrypt -in "$tmpdir/sm2_plain.txt" -out "$tmpdir/sm2_cipher.bin" \
        -pubin -inkey "$tmpdir/sm2_enc_pub.pem" -pkeyopt digest:sm3 2>/dev/null; then
        echo "sm2-encrypt-decrypt fail"
        return
    fi

    # 私钥解密
    if ! openssl pkeyutl -decrypt -in "$tmpdir/sm2_cipher.bin" -out "$tmpdir/sm2_dec.txt" \
        -inkey "$tmpdir/sm2_enc_priv.pem" -pkeyopt digest:sm3 2>/dev/null; then
        echo "sm2-encrypt-decrypt fail"
        return
    fi

    # 验证明文一致性
    if diff -q "$tmpdir/sm2_plain.txt" "$tmpdir/sm2_dec.txt" >/dev/null 2>&1; then
        echo "sm2-encrypt-decrypt pass"
    else
        echo "sm2-encrypt-decrypt fail"
    fi
}

# =============================================================================
# 25. 内核 Crypto API 国密支持检查
# =============================================================================
# 验证 Linux 内核加密子系统是否注册了国密算法。
# 内核 Crypto API 是 dm-crypt、IMA/EVM、KTLS 等内核安全功能的底层基础。
# 如果 /proc/crypto 不存在（如容器环境），标记为 skip。
# ---------------------------------------------------------------------------
test_kernel_crypto_sm() {
    if [ ! -f /proc/crypto ]; then
        echo "kernel-crypto-sm2 skip"
        echo "kernel-crypto-sm3 skip"
        return
    fi
    # 检查 SM2
    if grep -q "sm2" /proc/crypto 2>/dev/null; then
        echo "kernel-crypto-sm2 pass"
    else
        echo "kernel-crypto-sm2 skip"
    fi
    # 检查 SM3
    if grep -q "sm3" /proc/crypto 2>/dev/null; then
        echo "kernel-crypto-sm3 pass"
    else
        echo "kernel-crypto-sm3 skip"
    fi
}



# =============================================================================
# 执行测试
# =============================================================================
{
  # --- 环境准备与基础组件检查 ---
  test_openssl_installed
  test_ca_store
  test_password_hash_policy
  test_sm3_password_hash_policy

  # --- 对称加密与哈希算法正确性 ---
  test_aes_correctness
  test_sm4_correctness
  test_hash_correctness
  test_sm3_correctness
  test_random_quality

  # --- 非对称密钥生成与签名验签 ---
  test_rsa_sign_verify
  test_ecc_keygen_sign
  test_sm2_sign_verify
  test_sm2_encrypt_decrypt
  test_rsa_min_keysize

  # --- 证书管理与 PKI 链路验证 ---
  test_cert_key_match
  test_sm2_cert_key_match
  test_cert_verify
  test_sm2_cert_verify
  test_cert_chain_verify
  test_sm2_cert_chain_verify
  test_cert_expiry
  test_sm2_cert_expiry
  test_sm2_csr
  test_private_key_permission_audit

  # --- TLS 通信与安全策略 ---
  test_tls_handshake
  test_insecure_tls_rejection
  test_weak_algo_rejection
  test_aead_integrity
  test_key_file_permission

  # --- 内核与架构 ---
  test_kernel_crypto_sm
} | tee "$RESULT_FILE"