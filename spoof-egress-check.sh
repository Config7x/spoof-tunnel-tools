#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  spoof-egress-check v2 — تست باز بودن دیتاسنتر برای جعل Source IP
#
#  حالت ۱ — روی سرور خارجی (گوش می‌دهد و نتیجه نهایی را چاپ می‌کند):
#    bash <(curl -sL RAW/spoof-egress-check.sh) --listen
#
#  حالت ۲ — روی سرور ایرانی (پکت‌های تست را می‌فرستد):
#    bash <(curl -sL RAW/spoof-egress-check.sh) --target <IP سرور خارجی>
#
#  ترتیب: اول --listen روی خارج، بعد --target روی ایران.
#  در پایان، ترمینالِ سرور خارجی نتیجه هر سه پروتکل را چاپ می‌کند.
#
#  گزینه‌ها:
#    --spoof <IP>   آی‌پی جعلی (پیش‌فرض 1.1.1.1)
#    --ssh root@IP  حالت خودکار: اسکریپت روی ایران، tcpdump خارج را هم اجرا می‌کند
#    --dur <ثانیه>  مدت گوش دادن حالت --listen (پیش‌فرض 90)
# ─────────────────────────────────────────────────────────────
set -u
SPOOF="1.1.1.1"; TARGET=""; SSHT=""; MODE=""; DUR=90
while [ $# -gt 0 ]; do
  case "$1" in
    --listen) MODE="listen"; shift;;
    --target) MODE="send"; TARGET="$2"; shift 2;;
    --spoof)  SPOOF="$2"; shift 2;;
    --ssh)    SSHT="$2"; shift 2;;
    --dur)    DUR="$2"; shift 2;;
    *) echo "پارامتر ناشناخته: $1"; exit 1;;
  esac
done

# ───────────────────────── حالت گوش دادن (سرور خارجی) ─────────────────────────
if [ "$MODE" = "listen" ]; then
  command -v tcpdump >/dev/null || { echo "tcpdump نصب نیست: apt update && apt install -y tcpdump"; exit 1; }
  [ "$(id -u)" = "0" ] || { echo "با sudo اجرا کنید."; exit 1; }
  OUT=$(mktemp)
  echo "──────────────────────────────────────────────"
  echo " در حال گوش دادن به پکت‌های سورس $SPOOF  ($DUR ثانیه)"
  echo " حالا روی سرور ایرانی دستور --target را اجرا کنید"
  echo "──────────────────────────────────────────────"
  timeout "$DUR" tcpdump -nn -i any "src host $SPOOF" > "$OUT" 2>/dev/null
  C=$(LC_ALL=C grep -c "ICMP" "$OUT"); C=${C:-0}
  U=$(LC_ALL=C grep -c "UDP" "$OUT"); U=${U:-0}
  T=$(LC_ALL=C grep -c 'Flags \[S' "$OUT"); T=${T:-0}
  mark(){ [ "$1" -gt 0 ] && echo "✅ باز  ($1 پکت)" || echo "❌ بسته"; }
  echo
  echo "════════════ نتیجه نهایی ════════════"
  echo " ICMP     : $(mark "$C")"
  echo " UDP/DNS  : $(mark "$U")"
  echo " TCP SYN  : $(mark "$T")"
  echo "═════════════════════════════════════"
  if [ "$C" -gt 0 ] && [ "$U" -gt 0 ]; then echo "جمع‌بندی: دیتاسنتر فیلتر خروجی ندارد؛ برای اسپوف تانل قابل استفاده است 🎯"
  elif [ "$C" -gt 0 ] || [ "$U" -gt 0 ] || [ "$T" -gt 0 ]; then echo "جمع‌بندی: فقط برخی پروتکل‌ها رد می‌شوند؛ اسپوف تانل فقط با همان پروتکل کار می‌کند."
  else echo "جمع‌بندی: همه بسته شد؛ این دیتاسنتر BCP38 دارد — سراغ ارائه‌دهنده دیگر بروید."; echo "نکته: با --spoof یک IP از رنج خود سرور ایرانی هم تست کنید."
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
echo "Source جعلی     : $SPOOF"

RULE_ADDED=""
cleanup(){ [ -n "$RULE_ADDED" ] && $IPT -t nat -D POSTROUTING -d "$TARGET" -j SNAT --to-source "$SPOOF" 2>/dev/null; RULE_ADDED=""; }
trap cleanup EXIT

send(){ # $1=proto  $2=trigger
  $IPT -t nat -A POSTROUTING -p "$1" -d "$TARGET" -j SNAT --to-source "$SPOOF"
  RULE_ADDED=1
  eval "$2" >/dev/null 2>&1
  cleanup
  echo "  ✔ $1 ارسال شد"
}

echo "در حال ارسال تست‌ها..."
send icmp "ping -c 4 -W 2 $TARGET"
sleep 1
send udp "for i in 1 2 3; do echo spoof > /dev/udp/$TARGET/53; sleep 0.3; done"
sleep 1
send tcp "timeout 4 nc -z -w2 $TARGET 80; timeout 4 nc -z -w2 $TARGET 443; timeout 4 nc -z -w2 $TARGET 8080"
echo
if [ -n "$SSHT" ]; then
  echo "tcpdump روی سرور خارجی اجرا شد؛ خروجی را از همان سرور ببینید."
else
  echo "تمام شد ✅ حالا نتیجه نهایی روی ترمینال سرور خارجی چاپ شده است."
fi
