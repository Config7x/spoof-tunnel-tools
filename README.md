# spoof-egress-check

تست «باز بودن» دیتاسنتر برای جعل Source IP (اسپوف تانل)

برای اینکه بفهمید یک سرور ایرانی اجازه می‌دهد پکت با Source-IP جعلی (برای spoof-tunnel) بیرون برود یا نه.

## استفاده (روی سرور ایرانی)

### حالت ۱: با کلید SSH (تست کاملا خودکار)
اگر روی سرور خارجی کلید SSH ست شده باشد:
```bash
bash <(curl -sL https://raw.githubusercontent.com/Config7x/spoof-tunnel-tools/main/spoof-egress-check.sh) --ssh root@IP-سرور-خارجی
```
اسکریپت tcpdump را روی سرور خارجی اجرا می‌کند و نتیجه ✅/❌ هر پروتکل را خودکار چاپ می‌کند.

### حالت ۲: با پسورد SSH (دستی)
روی سرور خارجی یک ترمینال باز کن:
```bash
sudo tcpdump -nn -i any icmp
```
سپس روی سرور ایرانی:
```bash
bash <(curl -sL https://raw.githubusercontent.com/Config7x/spoof-tunnel-tools/main/spoof-egress-check.sh) --target IP-سرور-خارجی
```
در خروجی tcpdump اگر پکتی با سورس `1.1.1.1` (IP جعلی) رسید یعنی باز است.

## پروتکل‌های تست‌شده
| پروتکل | دستور tcpdump سمت خارج | معنی |
|---|---|---|
| ICMP | `sudo tcpdump -nn -i any icmp` | پایه‌ای‌ترین تست |
| UDP (DNS) | `sudo tcpdump -nn -i any udp` | شبیه ترافیک DNS |
| TCP SYN | `sudo tcpdump -nn -i any 'tcp[tcpflags] & tcp-syn != 0'` | حالت سخت‌تر |

## تفسیر نتیجه
- **ICMP باز + UDP باز** → دیتاسنتر فیلتر خروجی ندارد؛ قابل استفاده برای اسپوف تانل
- **فقط ICMP باز** → فقط همان حالت کار می‌کند
- **همه بسته** → BCP38 فعال است؛ سراغ ارائه‌دهنده دیگر بروید
- اگر همه بسته بود، با `--spoof` یک IP از همان رنج سرور هم تست کنید (بعضی فقط رنج خودشان را می‌گذارند بیرون)

## نکته مهم
ایران به ایران معمولا باز است؛ چیزی که باید تست کنید **ایران به خارج** است، چون Source-IP جعلی باید از لیست سفید خروج بین‌المللی عبور کند. برای پیدا کردن IPهای وایت‌لیست از ماژول tester پنل [spoof-tunnel](https://github.com/ParsaKSH/spoof-tunnel) استفاده کنید.
