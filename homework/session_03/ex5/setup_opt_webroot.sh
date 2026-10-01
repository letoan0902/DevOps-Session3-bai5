#!/usr/bin/env bash
# =============================================================================
# setup_opt_webroot.sh
# Thiết lập webroot an toàn tại /opt/my-app và chuyển site Nginx sang đó.
#
# Công việc của script (có thể chạy lại nhiều lần, kết quả không đổi):
#   1. Tạo /opt/my-app/html và /opt/my-app/logs
#   2. Sao chép mã nguồn từ /var/www/my-web/html (chỉ khi html còn trống)
#   3. Phân quyền: chủ sở hữu devops:www-data, thư mục 750, file 640,
#      thư mục logs 2770 (setgid)
#   4. Cài server block my-app.conf, gỡ symlink my-web.conf, kiểm tra
#      nginx -t rồi mới reload
#   5. Cài cấu hình logrotate cho /opt/my-app/logs
#
# Cách dùng (chạy trong thư mục chứa script, cùng với my-app.conf và
# my-app.logrotate):
#   bash setup_opt_webroot.sh
# =============================================================================

set -euo pipefail

# ---------------------------- Tham số cấu hình -------------------------------
APP_DIR="/opt/my-app"
SRC_DIR="/var/www/my-web/html"
APP_USER="devops"
APP_GROUP="www-data"

SITE_NEW="my-app.conf"
SITE_OLD="my-web.conf"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
LOGROTATE_TARGET="/etc/logrotate.d/my-app"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

# ------------------------ Yêu cầu quyền root ---------------------------------
# Nếu chưa phải root thì tự chạy lại bằng sudo (sudo sẽ hỏi mật khẩu).
if [[ $EUID -ne 0 ]]; then
    log "Cần quyền root, chạy lại bằng sudo"
    exec sudo bash "$0" "$@"
fi

# ------------------------ Kiểm tra điều kiện ---------------------------------
id "$APP_USER" > /dev/null 2>&1 || { log "Không tìm thấy user $APP_USER"; exit 1; }
getent group "$APP_GROUP" > /dev/null || { log "Không tìm thấy group $APP_GROUP"; exit 1; }
command -v nginx > /dev/null || { log "Chưa cài đặt nginx"; exit 1; }
[[ -f "$SCRIPT_DIR/my-app.conf" ]] || { log "Thiếu file $SCRIPT_DIR/my-app.conf"; exit 1; }
[[ -f "$SCRIPT_DIR/my-app.logrotate" ]] || { log "Thiếu file $SCRIPT_DIR/my-app.logrotate"; exit 1; }

# ------------------------ Bước 1: Tạo cấu trúc thư mục -----------------------
log "Bước 1: Tạo thư mục $APP_DIR/html và $APP_DIR/logs"
mkdir -p "$APP_DIR/html" "$APP_DIR/logs"

# ------------------------ Bước 2: Sao chép mã nguồn --------------------------
# Chỉ sao chép khi html còn trống để không ghi đè nội dung đã chỉnh sửa.
if [[ -z "$(ls -A "$APP_DIR/html")" ]]; then
    if [[ -d "$SRC_DIR" ]]; then
        log "Bước 2: Sao chép mã nguồn từ $SRC_DIR"
        cp -a "$SRC_DIR"/. "$APP_DIR/html/"
    else
        log "Bước 2: Không có $SRC_DIR, bỏ qua bước sao chép"
    fi
else
    log "Bước 2: $APP_DIR/html đã có dữ liệu, giữ nguyên"
fi

# ------------------------ Bước 3: Phân quyền ---------------------------------
# Lưu ý: không đụng vào file bên trong logs. File log do Nginx tạo và chuyển
# chủ sở hữu sang www-data; nếu chown/chmod đè lên, worker sẽ không mở lại
# được file khi logrotate gửi tín hiệu USR1.
log "Bước 3: Phân quyền sở hữu và truy cập"
find "$APP_DIR" -path "$APP_DIR/logs/*" -prune -o \
    -exec chown "$APP_USER:$APP_GROUP" {} +
find "$APP_DIR" -path "$APP_DIR/logs/*" -prune -o -type d -exec chmod 750 {} +
find "$APP_DIR" -path "$APP_DIR/logs/*" -prune -o -type f -exec chmod 640 {} +
# logs: group www-data được ghi, setgid để file mới kế thừa group www-data
chmod 2770 "$APP_DIR/logs"

# ------------------------ Bước 4: Cấu hình Nginx -----------------------------
log "Bước 4: Cài server block $SITE_NEW"
install -m 644 -o root -g root "$SCRIPT_DIR/my-app.conf" "$NGINX_AVAILABLE/$SITE_NEW"

# Ghi nhớ trạng thái cũ để quay lui nếu nginx -t thất bại.
old_was_enabled=0
if [[ -L "$NGINX_ENABLED/$SITE_OLD" ]]; then
    old_was_enabled=1
fi
new_was_enabled=0
if [[ -L "$NGINX_ENABLED/$SITE_NEW" ]]; then
    new_was_enabled=1
fi

ln -sfn "$NGINX_AVAILABLE/$SITE_NEW" "$NGINX_ENABLED/$SITE_NEW"
rm -f "$NGINX_ENABLED/$SITE_OLD"

log "Kiểm tra cú pháp: nginx -t"
if ! nginx -t; then
    log "nginx -t thất bại, quay lui cấu hình site"
    if [[ $old_was_enabled -eq 1 ]]; then
        ln -sfn "$NGINX_AVAILABLE/$SITE_OLD" "$NGINX_ENABLED/$SITE_OLD"
    fi
    if [[ $new_was_enabled -eq 0 ]]; then
        rm -f "$NGINX_ENABLED/$SITE_NEW"
    fi
    exit 1
fi

# ------------------------ Bước 5: Cấu hình logrotate -------------------------
log "Bước 5: Cài cấu hình logrotate $LOGROTATE_TARGET"
install -m 644 -o root -g root "$SCRIPT_DIR/my-app.logrotate" "$LOGROTATE_TARGET"

# ------------------------ Bước 6: Reload Nginx -------------------------------
log "Bước 6: Reload Nginx"
systemctl reload nginx

# ------------------------ Báo cáo trạng thái ---------------------------------
log "Hoàn tất. Trạng thái phân quyền hiện tại:"
ls -la "$APP_DIR/"
stat -c "%a %U:%G %n" "$APP_DIR" "$APP_DIR/html" "$APP_DIR/logs"
