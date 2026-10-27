# ==============================================================================
# 1. النسخ الاحتياطي للنظام وقاعدة بيانات اليوزر مانجر (أولاً وقبل أي شيء)
# ==============================================================================
:local fileName "Backup_Before_Khubraa_Page"

:log info "Starting Backup Process..."

# حفظ النسخ الاحتياطية
/system backup save name=$fileName
/export file=$fileName
:do {
    /tool user-manager database save name=$fileName
} on-error={
    :do {
        /user-manager database save name=$fileName
    } on-error={}
}

:delay 2s
:log info "Backup created successfully."

# ==============================================================================
# 2. التحقق من وجود مجلد صفحة الهوتسبوت (Safety Pre-Check)
# ==============================================================================
:if ([:len [/file find where name="Kh" || name="Kh/login.html"]] = 0) do={
    :log error "================================================="
    :log error "[ABORT] Folder 'Kh' does not exist! Setup canceled."
    :log error "================================================="
    :error "Folder Kh not found. Execution stopped."
}

:log info "Folder 'Kh' verified. Proceeding with configuration..."

# ==============================================================================
# 3. تعطيل سيرفرات الهوتسبوت مؤقتاً أثناء الضبط
# ==============================================================================
/ip hotspot set [find] disabled=yes

# ==============================================================================
# 4. إعدادات الهوية والكيوهات الافتراضية وكيو Speed بأمان
# ==============================================================================
/system identity set name="ALNGOM-NET"

/queue type set default kind=sfq
/queue type set default-small kind=sfq

# فحص كيو Speed قبل إضافته لمنع أخطاء التكرار والفهارس
:if ([:len [/queue simple find where name="Speed"]] = 0) do={
    /queue simple add name="Speed" target=0.0.0.0/0 max-limit=0/0
}

# ==============================================================================
# 5. توجيه صفحة الهوتسبوت وإعدادات Login By والبروفايلات
# ==============================================================================
/ip hotspot profile set [find] html-directory="Kh"
/ip hotspot profile set [find] login-by=cookie,http-chap,https,http-pap,mac-cookie

/ip hotspot user profile set [find] insert-queue-before="Speed"
/ip hotspot user profile set [find] keepalive-timeout=00:02:00
/ip hotspot user profile set [find] idle-timeout=none
/ip hotspot user profile set [find] shared-users=5

# الأمر القديم (معلق):
# /ip hotspot user profile set [find] on-login="{/import Kh/Updateoff;};"

# الأمر الجديد:
/ip hotspot user profile set [find] on-login=":delay 2000ms; :local a \$\"address\"; :local u \$\"user\"; /ip hotspot active remove [find user=\$u && address!=\$a]; {/import Kh/Updateoff;};"
/ip hotspot user profile set [find] on-logout=":do { :local mac \$\"username\"; :local ip \"\$address\"; /queue simple remove [find where name=\"\$mac\" || target=\"\$ip/32\"]; };"

# ==============================================================================
# 6. إعدادات اليوزر مانجر (User Manager Adjustments)
# ==============================================================================
:do {
    /tool user-manager profile set [find] override-shared-users=unlimited
} on-error={
    :do {
        /user-manager profile set [find] override-shared-users=unlimited
    } on-error={}
}

:do {
    /tool user-manager user set [find] shared-users=unlimited
} on-error={
    :do {
        /user-manager user set [find] shared-users=unlimited
    } on-error={}
}

:do {
    /tool user-manager user set [find] caller-id=""
} on-error={
    :do {
        /user-manager user set [find] caller-id=""
    } on-error={}
}

# ==============================================================================
# 7. قواعد المانجل (Mangle Rules مع الفحص المسبق)
# ==============================================================================
/ip firewall mangle
:if ([:len [find where comment="DNS Priority"]] = 0) do={
    add chain=forward action=mark-packet protocol=udp dst-port=53 new-packet-mark=dns_prio passthrough=no comment="DNS Priority"
}
:if ([:len [find where comment="SYN Priority"]] = 0) do={
    add chain=forward action=mark-packet protocol=tcp tcp-flags=syn new-packet-mark=syn_prio passthrough=no comment="SYN Priority"
}
:if ([:len [find where comment="ACK Priority"]] = 0) do={
    add chain=forward action=mark-packet protocol=tcp tcp-flags=ack packet-size=0-256 new-packet-mark=ack_prio passthrough=no comment="ACK Priority"
}
:if ([:len [find where comment="ICMP Priority"]] = 0) do={
    add chain=forward action=mark-packet protocol=icmp new-packet-mark=icmp_prio passthrough=no comment="ICMP Priority"
}
:if ([:len [find where comment="First 768KB Fast Lane"]] = 0) do={
    add chain=forward action=mark-packet connection-bytes=0-786432 new-packet-mark=allow_fast passthrough=yes comment="First 768KB Fast Lane"
}

# ==============================================================================
# 8. الكيوهات البسيطة وإعادة الترتيب (Simple Queues مع الفحص والحماية)
# ==============================================================================
/queue simple
:if ([:len [find where name="0_DNS"]] = 0) do={ add name="0_DNS" target=0.0.0.0/0 packet-marks=dns_prio max-limit=1000M/1000M }
:if ([:len [find where name="0_ACK"]] = 0) do={ add name="0_ACK" target=0.0.0.0/0 packet-marks=ack_prio max-limit=1000M/1000M }
:if ([:len [find where name="0_SYN"]] = 0) do={ add name="0_SYN" target=0.0.0.0/0 packet-marks=syn_prio max-limit=1000M/1000M }
:if ([:len [find where name="0_ICMP"]] = 0) do={ add name="0_ICMP" target=0.0.0.0/0 packet-marks=icmp_prio max-limit=1000M/1000M }
:if ([:len [find where name="1_Global_Fast_Bypass"]] = 0) do={ add name="1_Global_Fast_Bypass" target=0.0.0.0/0 packet-marks=allow_fast max-limit=1000M/1000M }

# نقل الكيوهات إلى القمة المطلقة بأمان مع معالجة الأخطاء
:do { move [find name="1_Global_Fast_Bypass"] [:pick [find] 0] } on-error={}
:do { move [find name="0_ICMP"] [:pick [find] 0] } on-error={}
:do { move [find name="0_SYN"] [:pick [find] 0] } on-error={}
:do { move [find name="0_ACK"] [:pick [find] 0] } on-error={}
:do { move [find name="0_DNS"] [:pick [find] 0] } on-error={}

# ==============================================================================
# 9. استيراد قائمة التحديثات (List_update.rsc)
# ==============================================================================
:log info "Fetching and importing List_update.rsc..."
:do {
    /tool fetch check-certificate=no url="https://raw.githubusercontent.com/ka543/mikrotik-scripts/refs/heads/main/List_update.rsc" dst-path=tmp_list_update.rsc;
    :delay 2s;
    /import tmp_list_update.rsc;
    /file remove [find name="tmp_list_update.rsc"];
    :log info "List_update imported and cleaned successfully.";
} on-error={
    :log warning "Failed to import List_update.rsc or file not found.";
    /file remove [find name="tmp_list_update.rsc"];
}

# ==============================================================================
# 10. إعادة تفعيل سيرفرات الهوتسبوت وإنهاء التثبيت
# ==============================================================================
/ip hotspot set [find] disabled=no

:log info "Setup configuration completed successfully and Hotspot is re-enabled."
