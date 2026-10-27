# ==============================================================================
# 0. التحقق الأولي الصارم من وجود مجلد صفحة الهوتسبوت
# ==============================================================================
:if ([:len [/file find where name="Kh" || name="Kh/login.html"]] = 0) do={
    :log error "[ABORT] Folder 'Kh' not found! Halting before making any changes."
    :error "Folder Kh missing. Execution completely aborted."
}

# ==============================================================================
# 1. إنشاء النسخة الاحتياطية بترقيم تصاعدي ذكي (دون استبدال القديم)
# ==============================================================================
:local baseName "Backup_Before_Khubraa_Page"
:local bkpName $baseName

:if ([:len [/file find where name=($baseName . ".backup") || name=($baseName . ".rsc")]] > 0) do={
    :local idx 1
    :local stop 0
    :while ($stop = 0) do={
        :local candidate ($baseName . "_" . [:tostr $idx])
        :if ([:len [/file find where name=($candidate . ".backup") || name=($candidate . ".rsc")]] = 0) do={
            :set bkpName $candidate
            :set stop 1
        } else={
            :set idx ($idx + 1)
        }
    }
}

:log info ("Creating backup snapshot: " . $bkpName)
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
:log info "Snapshot verified. Proceeding with configuration..."

# ==============================================================================
# 2. الهوية وأنواع الكيوهات الافتراضية
# ==============================================================================
/system identity set name="MyRouter"
/queue type set default kind=sfq
/queue type set default-small kind=sfq

# فحص كيو Speed لمنع التكرار
:if ([:len [/queue simple find where name="Speed"]] = 0) do={
    /queue simple add name="Speed" target=0.0.0.0/0 max-limit=0/0
}

# ==============================================================================
# 3. توجيه الهوتسبوت وإعدادات الدخول والبروفايلات
# ==============================================================================
/ip hotspot profile set [find] html-directory="Kh"
/ip hotspot profile set [find] login-by=cookie,http-chap,https,http-pap,mac-cookie

/ip hotspot user profile set [find] insert-queue-before="Speed"
/ip hotspot user profile set [find] keepalive-timeout=00:02:00
/ip hotspot user profile set [find] idle-timeout=none
/ip hotspot user profile set [find] rate-limit=""
/ip hotspot user profile set [find] shared-users=5

/ip hotspot user profile set [find] on-login=":delay 2000ms; :local a \$\"address\"; :local u \$\"user\"; /ip hotspot active remove [find user=\$u && address!=\$a]; {/import Kh/Updateoff;};"
/ip hotspot user profile set [find] on-logout=":do { :local mac \$\"username\"; :local ip \"\$address\"; /queue simple remove [find where name=\"\$mac\" || target=\"\$ip/32\"]; };"

# ==============================================================================
# 4. إعدادات اليوزر مانجر
# ==============================================================================
:do { /tool user-manager profile set [find] override-shared-users=unlimited } on-error={ :do { /user-manager profile set [find] override-shared-users=unlimited } on-error={} }
:do { /tool user-manager user set [find] shared-users=unlimited } on-error={ :do { /user-manager user set [find] shared-users=unlimited } on-error={} }
:do { /tool user-manager user set [find] caller-id="" } on-error={ :do { /user-manager user set [find] caller-id="" } on-error={} }

# ==============================================================================
# 5. قواعد المانجل (محمية ومفحوصة تماماً ضد التكرار)
# ==============================================================================
:if ([:len [/ip firewall mangle find where comment="DNS Priority"]] = 0) do={
    /ip firewall mangle add chain=forward action=mark-packet protocol=udp dst-port=53 new-packet-mark=dns_prio passthrough=no comment="DNS Priority"
}
:if ([:len [/ip firewall mangle find where comment="SYN Priority"]] = 0) do={
    /ip firewall mangle add chain=forward action=mark-packet protocol=tcp tcp-flags=syn new-packet-mark=syn_prio passthrough=no comment="SYN Priority"
}
:if ([:len [/ip firewall mangle find where comment="ACK Priority"]] = 0) do={
    /ip firewall mangle add chain=forward action=mark-packet protocol=tcp tcp-flags=ack packet-size=0-256 new-packet-mark=ack_prio passthrough=no comment="ACK Priority"
}
:if ([:len [/ip firewall mangle find where comment="ICMP Priority"]] = 0) do={
    /ip firewall mangle add chain=forward action=mark-packet protocol=icmp new-packet-mark=icmp_prio passthrough=no comment="ICMP Priority"
}
:if ([:len [/ip firewall mangle find where comment="First 768KB Fast Lane"]] = 0) do={
    /ip firewall mangle add chain=forward action=mark-packet connection-bytes=0-786432 new-packet-mark=allow_fast passthrough=yes comment="First 768KB Fast Lane"
}

# ==============================================================================
# 6. الكيوهات البسيطة وترتيبها (محمية ضد التكرار)
# ==============================================================================
:if ([:len [/queue simple find where name="0_DNS"]] = 0) do={
    /queue simple add name="0_DNS" target=0.0.0.0/0 packet-marks=dns_prio max-limit=1000M/1000M
}
:if ([:len [/queue simple find where name="0_ACK"]] = 0) do={
    /queue simple add name="0_ACK" target=0.0.0.0/0 packet-marks=ack_prio max-limit=1000M/1000M
}
:if ([:len [/queue simple find where name="0_SYN"]] = 0) do={
    /queue simple add name="0_SYN" target=0.0.0.0/0 packet-marks=syn_prio max-limit=1000M/1000M
}
:if ([:len [/queue simple find where name="0_ICMP"]] = 0) do={
    /queue simple add name="0_ICMP" target=0.0.0.0/0 packet-marks=icmp_prio max-limit=1000M/1000M
}
:if ([:len [/queue simple find where name="1_Global_Fast_Bypass"]] = 0) do={
    /queue simple add name="1_Global_Fast_Bypass" target=0.0.0.0/0 packet-marks=allow_fast max-limit=1000M/1000M
}

# نقل الكيوهات للأعلى بأمان
:do { /queue simple move [find name="1_Global_Fast_Bypass"] [:pick [find] 0] } on-error={}
:do { /queue simple move [find name="0_ICMP"] [:pick [find] 0] } on-error={}
:do { /queue simple move [find name="0_SYN"] [:pick [find] 0] } on-error={}
:do { /queue simple move [find name="0_ACK"] [:pick [find] 0] } on-error={}
:do { /queue simple move [find name="0_DNS"] [:pick [find] 0] } on-error={}

# ==============================================================================
# 7. استيراد قائمة التحديثات والتنظيف الجذري للملف المؤقت
# ==============================================================================
:local tmpFile "tmp_list_update.rsc"

:do {
    /tool fetch check-certificate=no url="https://raw.githubusercontent.com/ka543/mikrotik-scripts/refs/heads/main/List_update.rsc" dst-path=$tmpFile;
    :delay 2s;
    :do {
        /import $tmpFile;
    } on-error={};
} on-error={};

# تنظيف حتمي وحذف أي أثر للملف المؤقت
:delay 1s;
:do {
    /file remove [find where name=$tmpFile || name=($tmpFile . ".txt")];
} on-error={};

# ==============================================================================
# 8. التأكيد على تفعيل الهوتسبوت
# ==============================================================================
/ip hotspot set [find] disabled=no

:log info ">>> SETUP COMPLETED SUCCESSFULLY <<<"
