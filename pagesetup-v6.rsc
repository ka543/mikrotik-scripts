{
# ==============================================================================
# ⚙️ [قسم التعديل السريع لـ GitHub] - عدل المتغيرات هنا فقط قبل التشغيل
# ==============================================================================

# 1. اسم / هوية الراوتر الجديدة (اتركه فارغاً "" للحفاظ على اسم راوتر العميل كما هو دون تغيير):
:local routerIdentity "ALEMAD-NET"

# 2. بروفايلات الهوتسبوت المستثناة من أي تعديل (افصل بين الأسماء بفواصل منقوطة داخل الأقواس):
# مثال: :local excludedProfiles {"vip"; "admin_profile"; "special"}
:local excludedProfiles {}

# عداد الأخطاء العام لتتبع حالة التنفيذ النهائية في اللوق
:local errCount 0

:log info "=========================================================="
:log info ">>> [START] Starting Khubraa Setup for RouterOS v6 <<<"
:log info "=========================================================="

# ==============================================================================
# 0. التحقق الأولي الصارم من وجود مجلد صفحة الهوتسبوت (Kh أو flash/Kh)
# ==============================================================================
:log info "[SEC 0] Checking Hotspot HTML folder (Kh / flash/Kh)..."

:local htmlDir ""
:if ([:len [/file find where name="flash/Kh" || name="flash/Kh/login.html"]] > 0) do={
    :set htmlDir "flash/Kh"
} else={
    :if ([:len [/file find where name="Kh" || name="Kh/login.html"]] > 0) do={
        :set htmlDir "Kh"
    }
}

:if ($htmlDir = "") do={
    :log error "[SEC 0 - ERROR] Folder 'Kh' or 'flash/Kh' NOT found! Upload page folder first. Execution aborted."
    :error "Folder Kh missing. Execution completely aborted."
}
:log info ("[SEC 0 - OK] Hotspot folder verified at: " . $htmlDir)

# ==============================================================================
# 1. إنشاء النسخة الاحتياطية بترقيم تصاعدي ذكي آمن (دون استبدال القديم)
# ==============================================================================
:log info "[SEC 1] Creating safety backup snapshot..."

:local baseName "Backup_Before_Khubraa_Page"
:local bkpName $baseName

:if ([:len [/file find where name~$baseName]] > 0) do={
    :local idx 1
    :local stop 0
    :while ($stop = 0) do={
        :local candidate ($baseName . "_" . [:tostr $idx])
        :if ([:len [/file find where name~$candidate]] = 0) do={
            :set bkpName $candidate
            :set stop 1
        } else={
            :set idx ($idx + 1)
        }
    }
}

:do {
    /system backup save name=$bkpName
} on-error={
    :log error "[SEC 1 - ERROR] Failed to execute '/system backup save' (check disk space or permissions)."
}

:do {
    /export file=$bkpName
} on-error={
    :log error "[SEC 1 - ERROR] Failed to execute '/export' (check disk space or permissions)."
}

# حفظ قاعدة بيانات اليوزرمانجر (بأمان حتى لو لم تكن الحزمة مثبتة)
:do {
    [[:parse ("/tool user-manager database save name=\"" . $bkpName . "\"")]]
    :log info ("[SEC 1 - OK] User Manager v6 database backed up: " . $bkpName)
} on-error={
    :log warning "[SEC 1 - NOTE] User Manager database backup skipped (package not installed or unavailable)."
}

:delay 3s

# التحقق الإلزامي من نجاح النسخ الاحتياطي قبل البدء بأي تعديل
:if ([:len [/file find where name~$bkpName]] = 0) do={
    :log error "[SEC 1 - CRITICAL] Backup verification FAILED (no backup file found on disk)! Aborting to protect client router."
    :error "Backup failed. Execution stopped."
}
:log info ("[SEC 1 - OK] Backup & Export verified successfully: " . $bkpName)

# ==============================================================================
# 2. الهوية وأنواع الكيوهات الافتراضية وكيو Speed
# ==============================================================================
:log info "[SEC 2] Configuring Identity, Queue Types (SFQ), and Speed Queue..."
:local sec2Err 0

:if ($routerIdentity != "" && $routerIdentity != nil) do={
    :do {
        /system identity set name=$routerIdentity
        :log info ("[SEC 2 - OK] Router Identity set to: " . $routerIdentity)
    } on-error={
        :set sec2Err ($sec2Err + 1)
        :set errCount ($errCount + 1)
        :log error "[SEC 2 - ERROR] Failed to set Router Identity."
    }
} else={
    :log info "[SEC 2 - OK] Router Identity kept unchanged (empty parameter)."
}

:do {
    /queue type set default kind=sfq
    /queue type set default-small kind=sfq
} on-error={
    :set sec2Err ($sec2Err + 1)
    :set errCount ($errCount + 1)
    :log error "[SEC 2 - ERROR] Failed to set queue types (default / default-small) to SFQ."
}

# فحص كيو Speed لمنع التكرار
:if ([:len [/queue simple find where name="Speed"]] = 0) do={
    :do {
        /queue simple add name="Speed" target=0.0.0.0/0 max-limit=0/0
    } on-error={
        :set sec2Err ($sec2Err + 1)
        :set errCount ($errCount + 1)
        :log error "[SEC 2 - ERROR] Failed to create 'Speed' simple queue."
    }
}

:if ($sec2Err = 0) do={
    :log info "[SEC 2 - OK] Queue types (SFQ) and 'Speed' queue configured successfully."
}

# ==============================================================================
# 3. توجيه الهوتسبوت وتعديل البروفايلات (مع تطبيق نظام الاستثناء الصارم)
# ==============================================================================
:log info "[SEC 3] Configuring Hotspot Server Profiles & User Profiles..."
:local sec3Err 0

# أ) تعديل بروفايلات سيرفر الهوتسبوت غير المستثناة
/ip hotspot profile
:foreach hp in=[find] do={
    :local hpName [get $hp name]
    :local isEx 0
    :foreach ex in=$excludedProfiles do={
        :if ($ex != "" && $ex = $hpName) do={ :set isEx 1 }
    }
    :if ($isEx = 0) do={
        :do {
            set $hp html-directory=$htmlDir
            set $hp login-by=cookie,http-chap,https,http-pap,mac-cookie
            :log info ("[SEC 3 - OK] Hotspot Profile configured: " . $hpName)
        } on-error={
            :set sec3Err ($sec3Err + 1)
            :set errCount ($errCount + 1)
            :log error ("[SEC 3 - ERROR] Failed on Hotspot Profile '" . $hpName . "' (cause: likely 'https' in login-by without SSL certificate or invalid html-directory).")
        }
    } else={
        :log info ("[SEC 3 - SKIPPED] Hotspot Profile excluded: " . $hpName)
    }
}

# ب) تعديل بروفايلات مستخدمي الهوتسبوت غير المستثناة
:local onLoginCmd (":delay 2000ms; :local a \$\"address\"; :local u \$\"user\"; /ip hotspot active remove [find user=\$u && address!=\$a]; {/import " . $htmlDir . "/Updateoff;};")
:local onLogoutCmd ":do { :local mac \$\"username\"; :local ip \"\$address\"; /queue simple remove [find where name=\"\$mac\" || target=\"\$ip/32\"]; };"

/ip hotspot user profile
:foreach up in=[find] do={
    :local upName [get $up name]
    :local isEx 0
    :foreach ex in=$excludedProfiles do={
        :if ($ex != "" && $ex = $upName) do={ :set isEx 1 }
    }
    :if ($isEx = 0) do={
        :do {
            set $up insert-queue-before="Speed"
            set $up keepalive-timeout=00:02:00
            set $up idle-timeout=none
            set $up rate-limit=""
            set $up shared-users=5
            set $up on-login=$onLoginCmd
            set $up on-logout=$onLogoutCmd
            :log info ("[SEC 3 - OK] User Profile configured: " . $upName)
        } on-error={
            :set sec3Err ($sec3Err + 1)
            :set errCount ($errCount + 1)
            :log error ("[SEC 3 - ERROR] Failed on User Profile '" . $upName . "' (check if queue 'Speed' exists or profile is locked).")
        }
    } else={
        :log info ("[SEC 3 - SKIPPED] User Profile excluded: " . $upName)
    }
}

:if ($sec3Err = 0) do={
    :log info "[SEC 3 - OK] All non-excluded Hotspot profiles configured successfully."
}

# ==============================================================================
# 4. إعدادات اليوزر مانجر في الإصدار 6
# ==============================================================================
:log info "[SEC 4] Applying User Manager v6 settings..."

:do {
    [[:parse "/tool user-manager profile set [find] override-shared-users=unlimited; /tool user-manager user set [find] shared-users=unlimited; /tool user-manager user set [find] caller-id=\"\";"]]
    :log info "[SEC 4 - OK] User Manager v6 settings applied successfully."
} on-error={
    :log warning "[SEC 4 - SKIPPED] User Manager v6 not configured (package not installed or inaccessible)."
}

# ==============================================================================
# 5. قواعد المانجل (محمية ومفحوصة تماماً ضد التكرار)
# ==============================================================================
:log info "[SEC 5] Checking and adding Firewall Mangle priority rules..."
:local sec5Err 0

:if ([:len [/ip firewall mangle find where comment="DNS Priority"]] = 0) do={
    :do {
        /ip firewall mangle add chain=forward action=mark-packet protocol=udp dst-port=53 new-packet-mark=dns_prio passthrough=no comment="DNS Priority"
    } on-error={
        :set sec5Err ($sec5Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 5 - ERROR] Failed adding Mangle rule: DNS Priority"
    }
}
:if ([:len [/ip firewall mangle find where comment="SYN Priority"]] = 0) do={
    :do {
        /ip firewall mangle add chain=forward action=mark-packet protocol=tcp tcp-flags=syn new-packet-mark=syn_prio passthrough=no comment="SYN Priority"
    } on-error={
        :set sec5Err ($sec5Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 5 - ERROR] Failed adding Mangle rule: SYN Priority"
    }
}
:if ([:len [/ip firewall mangle find where comment="ACK Priority"]] = 0) do={
    :do {
        /ip firewall mangle add chain=forward action=mark-packet protocol=tcp tcp-flags=ack packet-size=0-256 new-packet-mark=ack_prio passthrough=no comment="ACK Priority"
    } on-error={
        :set sec5Err ($sec5Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 5 - ERROR] Failed adding Mangle rule: ACK Priority"
    }
}
:if ([:len [/ip firewall mangle find where comment="ICMP Priority"]] = 0) do={
    :do {
        /ip firewall mangle add chain=forward action=mark-packet protocol=icmp new-packet-mark=icmp_prio passthrough=no comment="ICMP Priority"
    } on-error={
        :set sec5Err ($sec5Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 5 - ERROR] Failed adding Mangle rule: ICMP Priority"
    }
}
:if ([:len [/ip firewall mangle find where comment="First 768KB Fast Lane"]] = 0) do={
    :do {
        /ip firewall mangle add chain=forward action=mark-packet connection-bytes=0-786432 new-packet-mark=allow_fast passthrough=yes comment="First 768KB Fast Lane"
    } on-error={
        :set sec5Err ($sec5Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 5 - ERROR] Failed adding Mangle rule: First 768KB Fast Lane"
    }
}

:if ($sec5Err = 0) do={
    :log info "[SEC 5 - OK] All 5 Mangle rules verified/added successfully."
}

# ==============================================================================
# 6. الكيوهات البسيطة وترتيبها في الأعلى (محمية ضد التكرار)
# ==============================================================================
:log info "[SEC 6] Checking, adding, and ordering priority Simple Queues..."
:local sec6Err 0

:if ([:len [/queue simple find where name="0_DNS"]] = 0) do={
    :do { /queue simple add name="0_DNS" target=0.0.0.0/0 packet-marks=dns_prio max-limit=1000M/1000M } on-error={
        :set sec6Err ($sec6Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 6 - ERROR] Failed adding Simple Queue: 0_DNS"
    }
}
:if ([:len [/queue simple find where name="0_ACK"]] = 0) do={
    :do { /queue simple add name="0_ACK" target=0.0.0.0/0 packet-marks=ack_prio max-limit=1000M/1000M } on-error={
        :set sec6Err ($sec6Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 6 - ERROR] Failed adding Simple Queue: 0_ACK"
    }
}
:if ([:len [/queue simple find where name="0_SYN"]] = 0) do={
    :do { /queue simple add name="0_SYN" target=0.0.0.0/0 packet-marks=syn_prio max-limit=1000M/1000M } on-error={
        :set sec6Err ($sec6Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 6 - ERROR] Failed adding Simple Queue: 0_SYN"
    }
}
:if ([:len [/queue simple find where name="0_ICMP"]] = 0) do={
    :do { /queue simple add name="0_ICMP" target=0.0.0.0/0 packet-marks=icmp_prio max-limit=1000M/1000M } on-error={
        :set sec6Err ($sec6Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 6 - ERROR] Failed adding Simple Queue: 0_ICMP"
    }
}
:if ([:len [/queue simple find where name="1_Global_Fast_Bypass"]] = 0) do={
    :do { /queue simple add name="1_Global_Fast_Bypass" target=0.0.0.0/0 packet-marks=allow_fast max-limit=1000M/1000M } on-error={
        :set sec6Err ($sec6Err + 1); :set errCount ($errCount + 1)
        :log error "[SEC 6 - ERROR] Failed adding Simple Queue: 1_Global_Fast_Bypass"
    }
}

# نقل الكيوهات للأعلى بأمان
:do { /queue simple move [find name="1_Global_Fast_Bypass"] [:pick [/queue simple find] 0] } on-error={ :log warning "[SEC 6 - WARN] Could not move 1_Global_Fast_Bypass to top." }
:do { /queue simple move [find name="0_ICMP"] [:pick [/queue simple find] 0] } on-error={ :log warning "[SEC 6 - WARN] Could not move 0_ICMP to top." }
:do { /queue simple move [find name="0_SYN"] [:pick [/queue simple find] 0] } on-error={ :log warning "[SEC 6 - WARN] Could not move 0_SYN to top." }
:do { /queue simple move [find name="0_ACK"] [:pick [/queue simple find] 0] } on-error={ :log warning "[SEC 6 - WARN] Could not move 0_ACK to top." }
:do { /queue simple move [find name="0_DNS"] [:pick [/queue simple find] 0] } on-error={ :log warning "[SEC 6 - WARN] Could not move 0_DNS to top." }

:if ($sec6Err = 0) do={
    :log info "[SEC 6 - OK] Priority Simple Queues verified and ordered at top."
}

# ==============================================================================
# 7. جدولة ضبط الكيو للبروفايلات الجديدة (تطبق للكل دون استثناء)
# ==============================================================================
:log info "[SEC 7] Configuring scheduler 'auto_set_queue_before'..."

:do {
    :if ([:len [/system scheduler find where name="auto_set_queue_before"]] = 0) do={
        /system scheduler add name="auto_set_queue_before" interval=5m on-event={
            /ip hotspot user profile
            :foreach p in=[find where insert-queue-before!="Speed"] do={
                set $p insert-queue-before="Speed"
            }
        }
    } else={
        /system scheduler set [find name="auto_set_queue_before"] interval=5m on-event={
            /ip hotspot user profile
            :foreach p in=[find where insert-queue-before!="Speed"] do={
                set $p insert-queue-before="Speed"
            }
        }
    }
    :log info "[SEC 7 - OK] Scheduler 'auto_set_queue_before' (5m) configured successfully."
} on-error={
    :set errCount ($errCount + 1)
    :log error "[SEC 7 - ERROR] Failed to add/update scheduler 'auto_set_queue_before'."
}

# ==============================================================================
# 8. استيراد قائمة التحديثات والتنظيف الجذري للملف المؤقت
# ==============================================================================
:log info "[SEC 8] Downloading and importing List_update.rsc..."

:local tmpFile "tmp_list_update.rsc"
:local fetchOk 0

:do {
    /tool fetch check-certificate=no url="https://raw.githubusercontent.com/ka543/mikrotik-scripts/refs/heads/main/List_update.rsc" dst-path=$tmpFile
    :set fetchOk 1
} on-error={
    :set errCount ($errCount + 1)
    :log error "[SEC 8 - ERROR] Failed to download List_update.rsc from GitHub (check Internet, DNS, or RouterOS TLS support)."
}

:if ($fetchOk = 1) do={
    :delay 2s
    :if ([:len [/file find where name=$tmpFile]] > 0) do={
        :do {
            /import $tmpFile
            :log info "[SEC 8 - OK] List_update.rsc imported successfully."
        } on-error={
            :set errCount ($errCount + 1)
            :log error "[SEC 8 - ERROR] List_update.rsc downloaded, but /import failed due to error inside List_update.rsc."
        }
    } else={
        :set errCount ($errCount + 1)
        :log error "[SEC 8 - ERROR] List_update.rsc file not found on disk after fetch."
    }
}

# تنظيف حتمي وحذف أي أثر للملف المؤقت
:delay 1s
:do {
    /file remove [find where name=$tmpFile || name=($tmpFile . ".txt") || name~"tmp_list_update"]
} on-error={}

# ==============================================================================
# 9. التأكيد على تفعيل الهوتسبوت والتنظيف الذاتي النهائي
# ==============================================================================
:log info "[SEC 9] Enabling Hotspot servers and cleaning temporary files..."

:do {
    /ip hotspot set [find] disabled=no
    :log info "[SEC 9 - OK] All Hotspot server(s) enabled."
} on-error={
    :set errCount ($errCount + 1)
    :log error "[SEC 9 - ERROR] Failed to enable Hotspot server(s)."
}

:delay 1s
:do {
    /file remove [find where name~"tmp_setup" || name~"tmp_list_update"]
} on-error={}
:do { /console clear-history } on-error={}

:log info "=========================================================="
:if ($errCount = 0) do={
    :log info ">>> [DONE] ALL SECTIONS APPLIED 100% FOR ROUTEROS V6 WITHOUT ERRORS <<<"
} else={
    :log warning (">>> [DONE WITH WARNINGS] ROUTEROS V6 SETUP FINISHED WITH " . [:tostr $errCount] . " ERROR(S) - CHECK LOGS ABOVE <<<")
}
:log info "=========================================================="
}
