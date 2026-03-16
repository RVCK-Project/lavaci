#!/bin/bash

set -x


#TEST_TMPDIR="/root/osv-scanner"
OUTPUT="$(pwd)/output"
mkdir -p "$OUTPUT"
RESULT_FILE="${OUTPUT}/result.txt"

#安装扫描工具
dnf install -y go jq
go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest
cp $(go env GOPATH)/bin/osv-scanner /usr/local/bin
#mkdir -p "${TEST_TMPDIR}"
#cd "${TEST_TMPDIR}"

#执行系统软件包漏洞扫描，输出扫描结果到result.json文件中
osv-scanner scan /var/lib/rpm --experimental-plugins os/rpm --format json --output "report.json"

# 处理扫描结果为lava可识别的结果

if [ ! -f "report.json" ]; then
    echo "Error: File $RESULT_JSON not found."
    exit 1
fi

# --- 提取包名、版本号和严重等级 ---
data=$(jq -r '
  .results[]? | 
  .packages[]? | 
  . as $pkg_info |
  .vulnerabilities[]? | 
  . as $vuln |
  select(.affected != null) |
  .affected[]? |
  select(.package != null and .package.name != null) |
  # 拼接 包名-版本号 作为唯一标识，同时提取严重等级
  "\($pkg_info.package.name)-\($pkg_info.package.version)\t\($vuln.database_specific.severity // "Unknown")"
' "report.json")

# 定义严重等级映射值
get_severity_score() {
    local level="$1"
    case "$(echo "$level" | tr '[:upper:]' '[:lower:]')" in
        critical) echo 1 ;;
        high)     echo 2 ;;
        medium)   echo 3 ;;
        low)      echo 4 ;;
        *)        echo 99 ;;
    esac
}

score_to_level() {
    local score="$1"
    case "$score" in
        1) echo "Critical" ;;
        2) echo "High" ;;
        3) echo "Medium" ;;
        4) echo "Low" ;;
        *) echo "Unknown" ;;
    esac
}

declare -A pkg_max_score
declare -A pkg_has_vuln

# 如果 data 为空，写入 pass 并退出
if [ -z "$data" ]; then
    echo "osv-scanner pass" |tee -a "$RESULT_FILE"
    exit 0
fi

# 遍历数据并聚合最高等级
while IFS=$'\t' read -r pkg_ver severity; do
    [ -z "$pkg_ver" ] && continue
    
    pkg_has_vuln["$pkg_ver"]=1
    current_score=$(get_severity_score "$severity")
    
    if [ -z "${pkg_max_score[$pkg_ver]}" ] || [ "$current_score" -lt "${pkg_max_score[$pkg_ver]}" ]; then
        pkg_max_score["$pkg_ver"]=$current_score
    fi
done <<< "$data"

# 获取所有包名-版本列表
all_packages=$(echo "$data" | cut -f1 | sort -u)

for pkg_ver in $all_packages; do
    if [ "${pkg_has_vuln[$pkg_ver]}" == "1" ]; then
        # 获取该包的最高风险分数
        max_score=${pkg_max_score[$pkg_ver]}
        # 将分数转换为文本等级 (Critical/High/Medium/Low)
        level_text=$(score_to_level "$max_score") 
        # 这里我们将 分数 作为 measurement， 等级文本 作为units
        # 输出格式: pkg-ver fail 1 Critical
        echo "${pkg_ver} fail ${max_score} ${level_text}" | tee -a "$RESULT_FILE"
    else
        echo "${pkg_ver} pass 0 None" | tee -a "$RESULT_FILE"
    fi
done
