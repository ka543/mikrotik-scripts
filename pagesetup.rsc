# تغيير أسماء المنافذ 1 و 2
/interface ethernet set [ find default-name=ether1 ] name=in1
/interface ethernet set [ find default-name=ether2 ] name=in2

# إنشاء البريدج باسم OUT
/interface bridge add name=OUT comment="By Khubraa for it"

# ضم المنافذ 4 و 5 للبريدج OUT
/interface bridge port
add bridge=OUT interface=ether4
add bridge=OUT interface=ether5

# تعيين عنوان IP للبريدج OUT (192.168.250.1 كبوابة افتراضية للشبكة الفرعية /28)
/ip address add address=192.168.250.1/28 interface=OUT comment="By Khubraa for it"

# إعداد خادم الـ DHCP لبريدج OUT
/ip pool add name=pool-OUT ranges=192.168.250.2-192.168.250.14
/ip dhcp-server add name=dhcp-OUT interface=OUT address-pool=pool-OUT disabled=no
/ip dhcp-server network add address=192.168.250.0/28 gateway=192.168.250.1 dns-server=8.8.8.8,1.1.1.1 comment="By Khubraa for it"

# --- برمجة نظام الدمج بواسطة Ammar Al-Sharabi ---
# التاريخ: 10/27/2026

/ip firewall mangle remove [find]
/ip route remove [find where !dynamic]
/ip firewall nat remove [find]
/ip dhcp-client remove [find]

/ip dhcp-client
add interface=in1 add-default-route=no use-peer-dns=yes use-peer-ntp=yes disabled=no comment="Client_WAN_1"
add interface=in2 add-default-route=no use-peer-dns=yes use-peer-ntp=yes disabled=no comment="Client_WAN_2"

/ip firewall nat
add chain=srcnat out-interface=in1 action=masquerade comment="NAT_WAN_1"
add chain=srcnat out-interface=in2 action=masquerade comment="NAT_WAN_2"

/ip firewall mangle
# منع الـ Loop للشبكة المحلية
add chain=prerouting dst-address-type=local action=accept in-interface=OUT

add chain=prerouting in-interface=in1 connection-mark=no-mark action=mark-connection new-connection-mark=wan1_conn passthrough=yes comment="PCC_RULE"
add chain=prerouting in-interface=OUT dst-address-type=!local per-connection-classifier=both-addresses-and-ports:2/0 action=mark-connection new-connection-mark=wan1_conn passthrough=yes comment="PCC_RULE"
add chain=prerouting connection-mark=wan1_conn in-interface=OUT action=mark-routing new-routing-mark=wan1_route passthrough=no comment="PCC_RULE"
add chain=output connection-mark=wan1_conn action=mark-routing new-routing-mark=wan1_route passthrough=yes comment="PCC_RULE"

add chain=prerouting in-interface=in2 connection-mark=no-mark action=mark-connection new-connection-mark=wan2_conn passthrough=yes comment="PCC_RULE"
add chain=prerouting in-interface=OUT dst-address-type=!local per-connection-classifier=both-addresses-and-ports:2/1 action=mark-connection new-connection-mark=wan2_conn passthrough=yes comment="PCC_RULE"
add chain=prerouting connection-mark=wan2_conn in-interface=OUT action=mark-routing new-routing-mark=wan2_route passthrough=no comment="PCC_RULE"
add chain=output connection-mark=wan2_conn action=mark-routing new-routing-mark=wan2_route passthrough=yes comment="PCC_RULE"

/ip route
# ملاحظة: تم دمج الـ IP مع المنفذ لحل مشكلة تشابه البوابات
add dst-address=0.0.0.0/0 gateway=100.64.0.1%in1 routing-mark=wan1_route distance=1 check-gateway=ping comment="PCC_ROUTE"
add dst-address=0.0.0.0/0 gateway=100.64.0.1%in2 routing-mark=wan2_route distance=1 check-gateway=ping comment="PCC_ROUTE"

# مسارات أساسية لخدمات الراوتر (Main Table)
add dst-address=0.0.0.0/0 gateway=100.64.0.1%in1 distance=1 check-gateway=ping comment="PCC_ROUTE"
add dst-address=0.0.0.0/0 gateway=100.64.0.1%in2 distance=2 comment="PCC_ROUTE"
