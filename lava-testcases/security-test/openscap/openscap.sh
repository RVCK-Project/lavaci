#!/bin/bash

set -x


TEST_TMPDIR="/root/openscap"
RESULT_FILE="${OUTPUT}/result.txt"

# 安装测试工具
yum install -y openscap scap-security-guide
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
# 获取系统版本
VERSION_ID=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
VERSION_NUM=$("$VERSION_ID" | tr -d '.')
echo "$VERSION_NUM"

# 执行oscap扫描，输出扫描结果到oscap-result.xml文件
oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_standard --results oscap-result.xml /usr/share/xml/scap/ssg/content/ssg-openeuler"$VERSION_NUM"-ds.xml || TRUE

# 用 xmlstarlet 提取规则 ID 和结果，转化为lava解析脚本所需出的纯文本格式（如test_name pass/fail）
# 结果值标准化：OpenSCAP 的结果包括 pass, fail, error, notapplicable, notchecked 等，LAVA脚本支持pass|fail|skip|unknown，故需将结果文件中的notapplicable/notchecked → skip，error → fail 或 unknown
sudo dnf install -y xmlstarlet
xmlstarlet sel \
  -N x="http://checklists.nist.gov/xccdf/1.2" \
  -t \
  -m "//x:TestResult/x:rule-result" \
  -v "@idref" -o " " -v "x:result" -n \
  oscap-result.xml | awk '
{
  rule = tolower( $ 1); res = tolower( $ 2)
  if (res == "pass") out = "pass"
  else if (res == "fail") out = "fail"
  else if (res == "error") out = "fail"
  else if (res ~ /^(notapplicable|notchecked|informational|notselected)$/) out = "skip"
  else out = "unknown"
  print rule " " out
}' > $RESULT_FILE