# ==============================================================================
# 1. النسخ الاحتياطي للنظام وقاعدة بيانات اليوزر مانجر (أولاً وقبل أي شيء)
# ==============================================================================
:local fileName "Backup_Before_Khubraa_Page"

:log info "Starting Backup Process..."

# تنفيذ أوامر الحفظ والتصدير
/system backup save name=$fileName
/export file=$fileName
:do {
    /tool user-manager database save name=$fileName
} on-error={
    :do {
        /user-manager database save name=$fileName
    } on-error={}
}

# انتظار ثانيتين لضمان اكتمال كتابة ملفات الباك آب على القرص
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
# 3. تعطيل جميع سيرفرات الهوتسبوت (مباشرة بعد الباك آب)
# ==============================================================================
/ip hotspot set [find] disabled=yes

# ==============================================================================
# 4. إعدادات الهوية والكيوهات الافتراضية
# ==============================================================================
/system identity set name="MyRouter"

/queue type set default kind=sfq
/queue type set default-small kind=sfq

/queue simple add name="Speed" target=0.0.0.0/0 max-limit=0/0 place-before=0

# ==============================================================================
# 5. توجيه صفحة الهوتسبوت وإعدادات Login By والبروفايلات
# ==============================================================================
# تعيين مجلد صفحة الهوتسبوت إلى Kh
/ip hotspot profile set [find] html-directory="Kh"

# ضبط طرق تسجيل الدخول (Login By)
/ip hotspot profile set [find] login-by=cookie,http-chap,https,http-pap,mac-cookie

# إعدادات بروفايلات المشتركين
/ip hotspot user profile set [find] insert-queue-before="Speed"

# جعل وقت التحقق من اتصال العميل (Keepalive) دقيقتين لجميع البروفايلات
/ip hotspot user profile set [find] keepalive-timeout=00:02:00

# جعل مهلة الخمول (Idle Timeout) بلا توقف (none)
/ip hotspot user profile set [find] idle-timeout=none

# تحديد عدد المستخدمين المسموح لهم بالدخول في نفس الوقت إلى 5 في جميع البروفايلات
/ip hotspot user profile set [find] shared-users=5

# الأمر القديم (معلق):
# /ip hotspot user profile set [find] on-login="{/import Kh/Updateoff;};"

# الأمر الجديد المضاف:
/ip hotspot user profile set [find] on-login=":delay 2000ms; :local a \$\"address\"; :local u \$\"user\"; /ip hotspot active remove [find user=\$u && address!=\$a]; {/import Kh/Updateoff;};"

/ip hotspot user profile set [find] on-logout=":do { :local mac \$\"username\"; :local ip \"\$address\"; /queue simple remove [find where name=\"\$mac\" || target=\"\$ip/32\"]; };"

# ==============================================================================
# 6. إعدادات اليوزر مانجر (User Manager Adjustments)
# ==============================================================================
# جعل عدد المستخدمين في جميع بروفايلات اليوزر منجر غير محدود
:do {
    /tool user-manager profile set [find] override-shared-users=unlimited
} on-error={
    :do {
        /user-manager profile set [find] override-shared-users=unlimited
    } on-error={}
}

# جعل عدد المستخدمين لجميع الكروت (الحسابات) الحالية غير محدود
:do {
    /tool user-manager user set [find] shared-users=unlimited
} on-error={
    :do {
        /user-manager user set [find] shared-users=unlimited
    } on-error={}
}

# مسح الماك أدرس (Caller ID) لجميع الكروت لفك ارتباطها بأول جهاز
:do {
    /tool user-manager user set [find] caller-id=""
} on-error={
    :do {
        /user-manager user set [find] caller-id=""
    } on-error={}
}

# ==============================================================================
# 7. قواعد المانجل (Mangle Rules)
# ==============================================================================
/ip firewall mangle
add chain=forward action=mark-packet protocol=udp dst-port=53 new-packet-mark=dns_prio passthrough=no comment="DNS Priority"
add chain=forward action=mark-packet protocol=tcp tcp-flags=syn new-packet-mark=syn_prio passthrough=no comment="SYN Priority"
add chain=forward action=mark-packet protocol=tcp tcp-flags=ack packet-size=0-256 new-packet-mark=ack_prio passthrough=no comment="ACK Priority"
add chain=forward action=mark-packet protocol=icmp new-packet-mark=icmp_prio passthrough=no comment="ICMP Priority"
add chain=forward action=mark-packet connection-bytes=0-786432 new-packet-mark=allow_fast passthrough=yes comment="First 768KB Fast Lane"

# ==============================================================================
# 8. الكيوهات البسيطة وإعادة الترتيب (Simple Queues & Ordering)
# ==============================================================================
/queue simple
add name="0_DNS" target=0.0.0.0/0 packet-marks=dns_prio max-limit=1000M/1000M
add name="0_ACK" target=0.0.0.0/0 packet-marks=ack_prio max-limit=1000M/1000M
add name="0_SYN" target=0.0.0.0/0 packet-marks=syn_prio max-limit=1000M/1000M
add name="0_ICMP" target=0.0.0.0/0 packet-marks=icmp_prio max-limit=1000M/1000M
add name="1_Global_Fast_Bypass" target=0.0.0.0/0 packet-marks=allow_fast max-limit=1000M/1000M

# نقل الكيوهات إلى القمة المطلقة
move [find name="1_Global_Fast_Bypass"] [:pick [find] 0]
move [find name="0_ICMP"] [:pick [find] 0]
move [find name="0_SYN"] [:pick [find] 0]
move [find name="0_ACK"] [:pick [find] 0]
move [find name="0_DNS"] [:pick [find] 0]

# ==============================================================================
# 9. استيراد قائمة التحديثات (List_update.rsc) وحذفها تلقائياً
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

:log info "Setup configuration completed successfully."
