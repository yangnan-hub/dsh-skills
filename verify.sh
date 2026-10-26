#!/usr/bin/env bash
# DSH skills 仓库健康检查 —— 每次 git pull 之后跑一次。
# 用法: ./verify.sh   (exit 0 = 通过, 1 = 有硬问题)
set -uo pipefail
cd "$(dirname "$0")" || exit 1
FAIL=0
WARN=0

echo "== 1/3 git 同步状态 =="
if git rev-parse --git-dir >/dev/null 2>&1; then
  dirty=$(git --no-optional-locks status --porcelain | wc -l | tr -d ' ')
  head=$(git rev-parse --short HEAD 2>/dev/null)
  up=$(git rev-parse --short '@{u}' 2>/dev/null || echo none)
  echo "  HEAD=$head  upstream=$up  dirty=$dirty"
  if [ "$dirty" -gt 0 ]; then echo "  WARN: 有 $dirty 个改动未提交"; WARN=$((WARN+1)); fi
  if [ "$up" != "none" ] && [ "$head" != "$up" ]; then
    echo "  WARN: 本地与远端不一致（先 git pull 或 git push）"; WARN=$((WARN+1))
  fi
else
  echo "  WARN: 不是 git 仓库，跳过同步检查"; WARN=$((WARN+1))
fi

echo "== 2/3 skill 结构 / frontmatter / 引用 =="
ruby -rdate -ryaml <<'RUBY' || FAIL=1
fails = 0
warns = 0
files = Dir.glob('*/SKILL.md').sort
if files.empty?
  puts '  FAIL: 没找到任何 <dir>/SKILL.md'
  exit 1
end
files.each do |f|
  dir = File.dirname(f)
  raw = begin
    File.read(f, encoding: 'UTF-8')
  rescue StandardError
    nil
  end
  unless raw&.valid_encoding?
    puts "  FAIL #{dir}: 不是合法 UTF-8"
    fails += 1
    next
  end
  fm = raw[/\A---\n(.*?)\n---/m, 1]
  h = begin
    YAML.safe_load(fm, permitted_classes: [Date])
  rescue StandardError
    nil
  end
  unless fm && h.is_a?(Hash)
    puts "  FAIL #{dir}: frontmatter 缺失或 YAML 解析失败"
    fails += 1
    next
  end
  name = h['name'].to_s
  desc = h['description'].to_s
  problems = []
  problems << 'name 不是 kebab-case' unless name =~ /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  problems << 'description 为空' if desc.strip.empty?
  if problems.empty?
    puts "  OK   #{dir}"
  else
    puts "  FAIL #{dir}: #{problems.join('; ')}"
    fails += 1
  end
  warns += 1 and puts "       WARN name(${name}) 与目录名(${dir}) 不一致（合法，但难查找）" if name != dir
  refs = raw.scan(%r{(?<![\w/.])((?:references|scripts|assets|examples)/[A-Za-z0-9_./\-]+)}).map(&:first).uniq
  refs.reject { |r| File.exist?(File.join(dir, r)) }.each do |m|
    puts "       WARN #{dir}: 引用的 #{m} 未落盘（可能是模板路径）"
    warns += 1
  end
end
puts "  skills=#{files.size}  fail=#{fails}"
exit(fails.zero? ? 0 : 1)
RUBY

echo "== 3/3 汇总 =="
if [ "$FAIL" -eq 0 ]; then
  echo "  PASS  结构检查通过（warn=${WARN}）"
else
  echo "  FAIL  结构检查未通过"
fi
echo "  提示: 本脚本只验文件层。技能是否真被 DSH 扫到，需在 DSH 里问一句带人名的触发语。"
exit "$FAIL"
