#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  spoof-egress-check — آیا این دیتاسنتر اجازه می‌دهد پکتِ
#  Source-IP جعلی از سرور بیرون برود؟ (تست سه‌پروتکلی)
#
#  اجرا روی سرور ایرانی:
#    sudo bash spoof-egress-check.sh --target <IP سرور خارجی> \
#         [--spoof <IP جعلی>] [--ssh root@<IP سرور خارجی>]
#
#  اگر --ssh بدهید، tcpdump روی سرور خارجی خودکار اجرا و نتیجه
#  خودکار خوانده می‌شود. اگر ندهید، اسکریپت دستور tcpdump را
#  چاپ می‌کند و شما خروجی همان سرور را نگاه می‌کنید.
# ─────────────────────────────────────────────────────────────
set -u
TARGET=""; SPOOF="1.1.1.1"; SSHT=""; WAIT=12
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2;;
    --spoof)  SPOOF="$2";  shift 2;;
    --ssh)    SSHT="$2";   shift 2;;
    *) echo "پارامتر ناشناخته: $1"; exit 1;;
  esac
done

[ "$(id -u)" = "0" ] || { echo "با sudo اجرا کنید."; exit 1; }
# اگر فقط --ssh داده شده، target همان IP است
if [ -z "$TARGET" ] && [ -n "$SSHT" ]; then
  TARGET="${SSHT##*@}"
fi
[ -n "$TARGET" ] || { echo "خطا: --target <IP سرور خارجی> یا --ssh root@<IP> لازم است."; exit 1; }

IPT=$(command -v iptables || true)
[ -n "$IPT" ] || { echo "iptables نیست. روی اوبونتو: apt update && apt install -y iptables tcpdump"; exit 1; }

echo "سرور خارجی هدف : $TARGET"
echo "Source جعلی    : $SPOOF"
echo

RULE_ADDED=""
cleanup(){ [ -n "$RULE_ADDED" ] && $IPT -t nat -D POSTROUTING -d "$TARGET" -j SNAT --to-source "$SPOOF" 2>/dev/null; }
trap cleanup EXIT

remote_dump(){ # $1 = proto filter , $2 = seconds
  if [ -n "$SSHT" ]; then
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$SSHT" \
      "timeout $2 tcpdump -nn -i any $1 2>/dev/null | grep -m1 '$SPOOF' && echo MATCH || echo NOMATCH" 2>/dev/null
  else
    echo "MANUAL"
  fi
}

run_proto(){ # $1=label  $2=iptables proto  $3=tcpdump filter  $4=trigger commands
  local label="$1" proto="$2" filt="$3" trig="$4"
  echo "──────── $label ────────"
  $IPT -t nat -A POSTROUTING -p "$proto" -d "$TARGET" -j SNAT --to-source "$SPOOF"
  RULE_ADDED=1
  if [ -n "$SSHT" ]; then
    ( sleep 1; eval "$trig" >/dev/null 2>&1 ) &
    local res; res=$(remote_dump "$filt" "$WAIT")
    [ "$res" = "MATCH" ] && echo "نتیجه: ✅ باز (پکتِ جعلی رسید)" || echo "نتیجه: ❌ بسته یا نامطمئن (چیزی نرسید)"
  else
    eval "$trig" >/dev/null 2>&1
    echo "روی سرور خارجی این را بزنید و ببینید پکت با سورس $SPOOF می‌رسد یا نه:"
    echo "  sudo tcpdump -nn -i any $filt"
  fi
  cleanup; RULE_ADDED=""
  echo
}

run_proto "ICMP" "icmp" "icmp" "ping -c 5 -W 2 $TARGET"
run_proto "UDP (شبیه DNS)" "udp" "udp" "for i in 1 2 3; do echo spoof > /dev/udp/$TARGET/53; done; sleep 1"
run_proto "TCP SYN" "tcp" "tcp and tcp[tcpflags] & tcp-syn != 0" "timeout 5 nc -z -w2 $TARGET 80; timeout 5 nc -z -w2 $TARGET 443"

cat <<'TXT'
─────────────────────────────────────────────
راهنمای نتیجه:
 • ICMP باز + UDP باز  → دیتاسنتر فیلتر خروجی ندارد؛ برای اسپوف تانل قابل استفاده است
 • فقط ICMP باز        → فقط برای همان حالت کار می‌کند؛ UDP/TCP را تست نکنید
 • همه بسته            → این دیتاسنتر BCP38 دارد؛ سراغ جای دیگر بروید
 • ❌ روی ICMP           → با --spoof یک رنج دیگر (همان رنج سرور) هم تست کنید؛
                        بعضی دیتاسنترها فقط رنج خودشان را می‌گذارند بیرون

بعد از پیدا کردن دیتاسنتر باز، مرحله دوم این است که بفهمید کدام
Source-IP جعلی واقعاً از لیست سفید بین‌المللی عبور می‌کند: از ماژول
tester در پنل spoof-tunnel روی رنج‌های ایرانی اسکن بگیرید.
TXT
