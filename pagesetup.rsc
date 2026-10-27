# ==============================================================================
# 0. التحقق الأولي الصارم من وجود مجلد صفحة الهوتسبوت
# ==============================================================================
:if ([:len [/file find where name="Kh" || name="Kh/login.html"]] = 0) do={
    :log error "[ABORT] Folder 'Kh' not found! Halting before making any changes."
    :error "Folder Kh missing. Execution completely aborted."
}

# ==============================================================================
# 1. إنشاء النسخة الاحتياطية لضمان الاسترجاع الكامل
# ==============================================================================
:local bkpName "Auto_Rollback_Backup"

:log info "Creating pre-execution rollback snapshot..."
/system backup save name=$bkpName
/export file=$bkpName
:do {
    /tool user-manager database save name=$bkpName
} on-error={
    :do {
        /user-manager database save name=$bkpName
    } on-error={}
}

:delay 2s
:log info "Snapshot verified. Starting transactional deployment..."

# ==============================================================================
# 2. كتلة التنفيذ المحمية (Transaction Block: All or Nothing)
# ==============================================================================
:do {
    # 2.1 تعطيل الهوتسبوت مؤقتاً أثناء التهيئة
    /ip hotspot set [find] disabled=yes

    # 2.2 الهوية والكيوهات الافتراضية وكيو Speed
    /system identity set name="ALNGOM-NET"
    /queue type set default kind=sfq
    /queue type set default-small kind=sfq

    :if ([:len [/queue simple find where name="Speed"]] = 0) do={
        /queue simple add name="Speed" target=0.0.0.0/0 max-limit=0/0
    }

    # 2.3 بروفايلات الهوتسبوت وسيرفر الدخول
    /ip hotspot profile set [find] html-directory="Kh"
    /ip hotspot profile set [find] login-by=cookie,http-chap,https,http-pap,mac-cookie

    /ip hotspot user profile set [find] insert-queue-before="Speed"
    /ip hotspot user profile set [find] keepalive-timeout=00:02:00
    /ip hotspot user profile set [find] idle-timeout=none
    /ip hotspot user profile set [find] shared-users=5

    /ip hotspot user profile set [find] on-login=":delay 2000ms; :local a \$\"address\"; :local u \$\"user\"; /ip hotspot active remove [find user=\$u && address!=\$a]; {/import Kh/Updateoff;};"
    /ip hotspot user profile set [find] on-logout=":do { :local mac \$\"username\"; :local ip \"\$address\"; /queue simple remove [find where name=\"\$mac\" || target=\"\$ip/32\"]; };"

    # 2.4 تعديلات اليوزر مانجر
    :do { /tool user-manager profile set [find] override-shared-users=unlimited } on-error={ :do { /user-manager profile set [find] override-shared-users=unlimited } on-error={} }
    :do { /tool user-manager user set [find] shared-users=unlimited } on-error={ :do { /user-manager user set [find] shared-users=unlimited } on-error={} }
    :do { /tool user-manager user set [find] caller-id="" } on-error={ :do { /user-manager user set [find] caller-id="" } on-error={} }

    # 2.5 قواعد المانجل
    /ip firewall mangle
    :if ([:len [find where comment="DNS Priority"]] = 0) do={ add chain=forward action=mark-packet protocol=udp dst-port=53 new-packet-mark=dns_prio passthrough=no comment="DNS Priority" }
    :if ([:len [find where comment="SYN Priority"]] = 0) do={ add chain=forward action=mark-packet protocol=tcp tcp-flags=syn new-packet-mark=syn_prio passthrough=no comment="SYN Priority" }
    :if ([:len [find where comment="ACK Priority"]] = 0) do={ add chain=forward action=mark-packet protocol=tcp tcp-flags=ack packet-size=0-256 new-packet-mark=ack_prio passthrough=no comment="ACK Priority" }
    :if ([:len [find where comment="ICMP Priority"]] = 0) do={ add chain=forward action=mark-packet protocol=icmp new-packet-mark=icmp_prio passthrough=no comment="ICMP Priority" }
    :if ([:len [find where comment="First 768KB Fast Lane"]] = 0) do={ add chain=forward action=mark-packet connection-bytes=0-786432 new-packet-mark=allow_fast passthrough=yes comment="First 768KB Fast Lane" }

    # 2.6 الكيوهات البسيطة وترتيبها
    /queue simple
    :if ([:len [find where name="0_DNS"]] = 0) do={ add name="0_DNS" target=0.0.0.0/0 packet-marks=dns_prio max-limit=1000M/1000M }
    :if ([:len [find where name="0_ACK"]] = 0) do={ add name="0_ACK" target=0.0.0.0/0 packet-marks=ack_prio max-limit=1000M/1000M }
    :if ([:len [find where name="0_SYN"]] = 0) do={ add name="0_SYN" target=0.0.0.0/0 packet-marks=syn_prio max-limit=1000M/1000M }
    :if ([:len [find where name="0_ICMP"]] = 0) do={ add name="0_ICMP" target=0.0.0.0/0 packet-marks=icmp_prio max-limit=1000M/1000M }
    :if ([:len [find where name="1_Global_Fast_Bypass"]] = 0) do={ add name="1_Global_Fast_Bypass" target=0.0.0.0/0 packet-marks=allow_fast max-limit=1000M/1000M }

    move [find name="1_Global_Fast_Bypass"] [:pick [find] 0]
    move [find name="0_ICMP"] [:pick [find] 0]
    move [find name="0_SYN"] [:pick [find] 0]
    move [find name="0_ACK"] [:pick [find] 0]
    move [find name="0_DNS"] [:pick [find] 0]

    # 2.7 جلب واستيراد ملف List_update.rsc
    /tool fetch check-certificate=no url="https://raw.githubusercontent.com/ka543/mikrotik-scripts/refs/heads/main/List_update.rsc" dst-path=tmp_list_update.rsc;
    :delay 2s;
    /import tmp_list_update.rsc;
    /file remove [find name="tmp_list_update.rsc"];

    # 2.8 إعادة تفعيل الهوتسبوت بعد إتمام كل الخطوات بنجاح
    /ip hotspot set [find] disabled=no

    :log info ">>> ALL TASKS APPLIED SUCCESSFULLY (100%) <<<";

} on-error={
    # ==============================================================================
    # 3. خطة التراجع الفوري (Automatic Rollback Trigger)
    # ==============================================================================
    :log error "================================================================"
    :log error "[CRITICAL ERROR] Script encountered a failure during execution!"
    :log error "[ROLLBACK] Reverting system back to snapshot: Auto_Rollback_Backup"
    :log error "================================================================"

    # تنظيف أي ملفات مؤقتة
    /file remove [find name="tmp_list_update.rsc"];

    # إعادة تشغيل الراوتر وتحميل النسخة الاحتياطية الأصلية تلقائياً
    /system backup load name="Auto_Rollback_Backup.backup" password=""
}
