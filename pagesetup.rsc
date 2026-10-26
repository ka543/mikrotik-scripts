# ==========================================
# 0. Backup System & UserManager Database
# ==========================================
:log info "Starting Backup Process..."

# 1. Full System Backup (.backup) & Export (.rsc)
/system backup save name="Pre_Setup_Backup"
/export file="Pre_Setup_Config"

# 2. User Manager Database Backup (compatible with RouterOS v6 & v7)
:do {
    # For RouterOS v6
    /tool user-manager database save name="Pre_Setup_UM"
} on-error={
    # For RouterOS v7
    :do {
        /user-manager database save name="Pre_Setup_UM"
    } on-error={
        :log warning "User Manager package not installed or failed to backup"
    }
}

# Wait 3 seconds to ensure disk write is complete
:delay 3s
:log info "Backup completed successfully. Applying configurations..."

# ==========================================
# 1. System Identity & Queue Types
# ==========================================
/system identity set name="MyRouter"

/queue type set default kind=sfq
/queue type set default-small kind=sfq

/queue simple add name="Speed" target=0.0.0.0/0 max-limit=0/0 place-before=0

/ip hotspot user profile set [find] insert-queue-before="Speed"
/ip hotspot user profile set [find] on-login="{/import Kh/Updateoff;};"
/ip hotspot user profile set [find] on-logout=":do { :local mac \$\"username\"; :local ip \"\$address\"; /queue simple remove [find where name=\"\$mac\" || target=\"\$ip/32\"]; };"

# ==========================================
# 2. Mangle Rules
# ==========================================
/ip firewall mangle
add chain=forward action=mark-packet protocol=udp dst-port=53 new-packet-mark=dns_prio passthrough=no comment="DNS Priority"
add chain=forward action=mark-packet protocol=tcp tcp-flags=syn new-packet-mark=syn_prio passthrough=no comment="SYN Priority"
add chain=forward action=mark-packet protocol=tcp tcp-flags=ack packet-size=0-256 new-packet-mark=ack_prio passthrough=no comment="ACK Priority"
add chain=forward action=mark-packet protocol=icmp new-packet-mark=icmp_prio passthrough=no comment="ICMP Priority"
add chain=forward action=mark-packet connection-bytes=0-786432 new-packet-mark=allow_fast passthrough=yes comment="First 768KB Fast Lane"

# ==========================================
# 3. Simple Queues & Ordering
# ==========================================
/queue simple
add name="0_DNS" target=0.0.0.0/0 packet-marks=dns_prio max-limit=1000M/1000M
add name="0_ACK" target=0.0.0.0/0 packet-marks=ack_prio max-limit=1000M/1000M
add name="0_SYN" target=0.0.0.0/0 packet-marks=syn_prio max-limit=1000M/1000M
add name="0_ICMP" target=0.0.0.0/0 packet-marks=icmp_prio max-limit=1000M/1000M
add name="1_Global_Fast_Bypass" target=0.0.0.0/0 packet-marks=allow_fast max-limit=1000M/1000M

# Re-order to the top
move [find name="1_Global_Fast_Bypass"] [:pick [find] 0]
move [find name="0_ICMP"] [:pick [find] 0]
move [find name="0_SYN"] [:pick [find] 0]
move [find name="0_ACK"] [:pick [find] 0]
move [find name="0_DNS"] [:pick [find] 0]

:log info "Setup configuration completed successfully."
