#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  spoof-egress-check v3 — تست باز بودن دیتاسنتر برای جعل Source IP
#
#  حالت ۱ — روی سرور خارجی (گوش می‌دهد و نتیجه نهایی را چاپ می‌کند):
#    bash <(curl -sL RAW/spoof-egress-check.sh) --listen
#
#  حالت ۲ — روی سرور ایرانی (پکت‌های تست را می‌فرستد):
#    bash <(curl -sL RAW/spoof-egress-check.sh) --target <IP سرور خارجی>
#
#  ترتیب: اول --listen روی خارج، بعد --target روی ایران.
#  در پایان، ترمینالِ سرور خارجی نتیجه همه IPها و پروتکل‌ها را چاپ می‌کند.
#
#  v3: هر تست با «چند» IP جعلی و پکت بیشتر انجام می‌شود
#      (پیش‌فرض: 1.1.1.1, 8.8.8.8, 9.9.9.9)
#
#  گزینه‌ها:
#    --spoof a,b,c  لیست IPهای جعلی (هر دو طرف باید یکسان باشد)
#    --dur <ثانیه>   مدت گوش دادن (پیش‌فرض 120)
#    --ssh root@IP   حالت خودکار روی ایران (نیازمند کلید SSH)
# ─────────────────────────────────────────────────────────────
set -u
SPOOFS="1.1.1.1,8.8.8.8,9.9.9.9"; TARGET=""; SSHT=""; MODE=""; DUR=120
while [ $# -gt 0 ]; do
  case "$1" in
    --listen) MODE="listen"; shift;;
    --target) MODE="send"; TARGET="$2"; shift 2;;
    --spoof)  SPOOFS="$2"; shift 2;;
    --ssh)    SSHT="$2"; shift 2;;
    --dur)    DUR="$2"; shift 2;;
    *) echo "پارامتر ناشناخته: $1"; exit 1;;
  esac
done
IFS=',' read -r -a SPLIST <<< "$SPOOFS"
[ "${#SPLIST[@]}" -gt 0 ] || { echo "لیست --spoof خالی است"; exit 1; }

# ───────────────────────── حالت گوش دادن (سرور خارجی) ─────────────────────────
if [ "$MODE" = "listen" ]; then
  command -v tcpdump >/dev/null || { echo "tcpdump نصب نیست: apt update && apt install -y tcpdump"; exit 1; }
  [ "$(id -u)" = "0" ] || { echo "با sudo اجرا کنید."; exit 1; }
  OUT=$(mktemp)
  FILTER="src host ${SPLIST[0]}"
  for ip in "${SPLIST[@]:1}"; do FILTER="$FILTER or src host $ip"; done
  echo "──────────────────────────────────────────────"
  echo " گوش دادن به پکت‌های سورس: ${SPLIST[*]}"
  echo " مدت: $DUR ثانیه — حالا روی سرور ایرانی --target را اجرا کنید"
  echo "──────────────────────────────────────────────"
  timeout "$DUR" tcpdump -nn -i any "$FILTER" > "$OUT" 2>/dev/null
  echo
  echo "══════════════════ نتیجه نهایی ══════════════════"
  ANY_OPEN=0
  for ip in "${SPLIST[@]}"; do
    C=$(LC_ALL=C grep -c " $ip > .*ICMP\|ICMP.* $ip >" "$OUT"); C=${C:-0}
    C=$(LC_ALL=C grep "ICMP" "$OUT" | LC_ALL=C grep -c "$ip >"); C=${C:-0}
    U=$(LC_ALL=C grep "UDP" "$OUT" | LC_ALL=C grep -c "$ip\."); U=${U:-0}
    T=$(LC_ALL=C grep 'Flags \[S' "$OUT" | LC_ALL=C grep -c "$ip\."); T=${T:-0}
    mk(){ [ "$1" -gt 0 ] && echo "✅($1)" || echo "❌"; }
    echo " IP $ip →  ICMP:$(mk "$C")  UDP:$(mk "$U")  TCP:$(mk "$T")"
    [ "$C" -gt 0 ] || [ "$U" -gt 0 ] || [ "$T" -gt 0 ] && ANY_OPEN=1
  done
  echo "══════════════════════════════════════════════════"
  if [ "$ANY_OPEN" = "1" ]; then
    echo " جمع‌بندی: حداقل یک IP جعلی از این دیتاسنتر رد می‌شود 🎯"
    echo " (اسپوف تانل با همان IP/پروتکل‌های باز قابل پیاده‌سازی است)"
  else
    echo " جمع‌بندی: هیچ IP جعلی رد نشد؛ این دیتاسنتر BCP38 کامل دارد."
    echo " نکته: با --spoof چند IP از رنج خود سرور ایرانی هم تست کنید."
  fi
  rm -f "$OUT"; exit 0
fi

# ───────────────────────── حالت ارسال (سرور ایرانی) ─────────────────────────
[ "$MODE" = "send" ] || { echo "حالت را مشخص کنید: --listen (روی خارج) یا --target <IP> (روی ایران)"; exit 1; }
[ "$(id -u)" = "0" ] || { echo "با sudo اجرا کنید."; exit 1; }
IPT=$(command -v iptables || true)
[ -n "$IPT" ] || { echo "iptables نیست: apt update && apt install -y iptables"; exit 1; }
if [ -z "$TARGET" ] && [ -n "$SSHT" ]; then TARGET="${SSHT##*@}"; fi
[ -n "$TARGET" ] || { echo "خطا: --target <IP سرور خارجی> لازم است."; exit 1; }
echo "سرور خارجی هدف : $TARGET"
echo "IPهای جعلی     : ${SPLIST[*]}"

RULE_ADDED=""
cleanup(){ [ -n "$RULE_ADDED" ] && $IPT -t nat -D POSTROUTING -d "$TARGET" -j SNAT --to-source "$RULE_ADDED" 2>/dev/null; RULE_ADDED=""; }
trap cleanup EXIT

send(){ # $1=proto  $2=spoof  $3=trigger
  $IPT -t nat -A POSTROUTING -p "$1" -d "$TARGET" -j SNAT --to-source "$2"
  RULE_ADDED="$2"
  eval "$3" >/dev/null 2>&1
  cleanup
}

echo "در حال ارسال تست‌ها (هر IP: 8 پینگ + 8 UDP + 4 SYN)..."
for ip in "${SPLIST[@]}"; do
  echo "  ✔ تست $ip"
  send icmp "$ip" "ping -c 8 -i 0.3 -W 2 $TARGET"
  send udp  "$ip" "for i in 1 2 3 4 5 6 7 8; do echo s > /dev/udp/$TARGET/53; sleep 0.2; done"
  send tcp  "$ip" "for p in 80 443 8080 22; do timeout 3 nc -z -w2 $TARGET $p; done"
  sleep 1
done
echo
echo "تمام شد ✅ نتیجه نهایی روی ترمینال سرور خارجی چاپ شده است."
