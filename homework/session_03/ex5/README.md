# Bài 5 - Thiết lập thư mục Web an toàn tại phân vùng hệ thống (/opt/)

Môn DevOps - Session 03.

## 1. Mục tiêu và bối cảnh

Doanh nghiệp chuẩn bị đưa website vào chạy Production và yêu cầu cô lập hoàn toàn mã nguồn web cùng logs của dự án ra khỏi vị trí mặc định của hệ điều hành. Bài này chuyển website tĩnh và logs sang `/opt/my-app/`, đồng thời phân quyền để phân tách rõ vai trò:

- `devops` (uid 1001): tài khoản quản trị thường, toàn quyền đọc/ghi mã nguồn, không cần `sudo`.
- `www-data` (uid/gid 33): tài khoản chạy worker của Nginx, chỉ đọc mã nguồn, được ghi vào thư mục logs.

Các yêu cầu cần đạt:

1. Mã nguồn tại `/opt/my-app/html/`, logs tại `/opt/my-app/logs/`.
2. Toàn bộ `/opt/my-app/` thuộc `devops:www-data`.
3. `devops` đọc/ghi được; `www-data` đọc và thực thi (duyệt) thư mục web, ghi được vào thư mục logs.
4. Server block Nginx ghi `access_log` và `error_log` trực tiếp vào đường dẫn mới.
5. Nginx hoạt động bình thường (không 403) và tự ghi log vào tệp chỉ định.

## 2. Môi trường thực hiện

| Thành phần | Giá trị |
|---|---|
| Máy chủ | Ubuntu 24.04.3 LTS, hostname `halo`, IP `103.116.104.228` |
| Tài khoản quản trị | `devops` (uid 1001, gid 1001, nhóm `sudo`, sudo có hỏi mật khẩu) |
| Tài khoản Nginx | `www-data` (uid 33, gid 33) |
| Nginx | `nginx/1.24.0 (Ubuntu)`; master chạy `root`, worker chạy `www-data` |
| Kết nối | `ssh -p 2222 -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228` |
| Máy cá nhân | Windows, Git Bash, IP công cộng `113.161.72.19`, curl 8.15.0 |
| Thời gian thực hiện | 2026-10-02 (thứ Sáu), khoảng 15:02 đến 15:50, múi giờ +0700 |

Hiện trạng đầu bài: site `my-web` chạy cổng 80 với root `/var/www/my-web/html` (file `/etc/nginx/sites-available/my-web.conf`, `listen 80 default_server`). Trong bài này tạo site mới `my-app` thay thế vai trò site chính trên cổng 80, sao chép mã nguồn (`index.html`, `404.html`) sang `/opt/my-app/html/`, và gỡ symlink `my-web.conf` khỏi `sites-enabled` để tránh trùng `default_server`. File gốc `my-web.conf` vẫn được giữ trong `sites-available` để có thể quay lui.

## 3. Vì sao dùng /opt theo chuẩn FHS

Theo Filesystem Hierarchy Standard (FHS), `/opt` dành cho phần mềm add-on, tức các ứng dụng không thuộc bộ cài mặc định của hệ điều hành và tự đóng gói cấu trúc riêng. Đặt site tại đây cô lập mã nguồn và logs khỏi `/var/www` mặc định của gói hệ điều hành. So sánh:

| Tiêu chí | `/var/www` (mặc định gói hệ điều hành) | `/opt/my-app` (tự quản lý) |
|---|---|---|
| Nguồn gốc | Do gói `nginx`/`apache2` tạo và gắn với vòng đời gói | Do đội dự án sở hữu hoàn toàn |
| Sao lưu | Phải chọn lọc từng thư mục con | Sao lưu hoặc di chuyển cả `/opt/my-app` là đủ mã nguồn và logs |
| Phân vùng riêng | Khó tách khi dữ liệu nằm rải rác | Dễ mount phân vùng hoặc ổ đĩa riêng vào `/opt` hoặc `/opt/my-app`, giới hạn dung lượng, tránh log làm đầy `/` |

Cây thư mục mục tiêu:

```
/
+-- opt/                      (root:root, 755)
    +-- my-app/               (devops:www-data, 750)
        |-- html/             (devops:www-data, 750)
        |   |-- index.html    (devops:www-data, 640)
        |   +-- 404.html      (devops:www-data, 640)
        +-- logs/             (devops:www-data, 2770, setgid)
            |-- access.log    (www-data:www-data, 644, do Nginx tạo)
            +-- error.log     (www-data:www-data, 644, do Nginx tạo)
```

## 4. Bước 1 - Tạo cấu trúc và sao chép mã nguồn

Hiện trạng trước khi thay đổi: `/var/www/my-web/html/` chứa `404.html` (2036 byte) và `index.html` (623 byte); `/opt/my-app/` chưa tồn tại.

Tạo thư mục (cần `sudo` vì `/opt` thuộc `root:root` 755). Ngay sau khi tạo, cả hai thư mục còn thuộc `root:root`:

```
devops@halo:~$ sudo mkdir -p /opt/my-app/html /opt/my-app/logs
[sudo] password for devops: 
devops@halo:~$ ls -la /opt/my-app/
total 16
drwxr-xr-x 4 root root 4096 Oct  2 15:06 .
drwxr-xr-x 3 root root 4096 Oct  2 15:06 ..
drwxr-xr-x 2 root root 4096 Oct  2 15:06 html
drwxr-xr-x 2 root root 4096 Oct  2 15:06 logs
```

Sao chép mã nguồn bằng `cp -a` (giữ nguyên thuộc tính, bao gồm cả file ẩn nhờ dạng `nguồn/.`):

```
devops@halo:~$ sudo cp -a /var/www/my-web/html/. /opt/my-app/html/
devops@halo:~$ ls -la /opt/my-app/html/
total 16
drwxr-x--- 2 devops www-data 4096 Oct  2 10:07 .
drwxr-xr-x 4 root   root     4096 Oct  2 15:06 ..
-rw-r----- 1 devops www-data 2036 Oct  2 10:07 404.html
-rw-r----- 1 devops www-data  623 Oct  1 15:03 index.html
devops@halo:~$ diff -rq /var/www/my-web/html /opt/my-app/html && echo "Hai thư mục có nội dung giống nhau"
Hai thư mục có nội dung giống nhau
```

Nhận xét: `cp -a` chạy dưới `sudo` vẫn giữ chủ sở hữu, quyền và thời gian của nguồn (`devops:www-data`, 750/640), kể cả thuộc tính của chính thư mục `html`. Tuy nhiên thư mục gốc `/opt/my-app` và `logs` vẫn thuộc `root:root`, nên bước phân quyền kế tiếp là bắt buộc để đồng bộ toàn bộ cây về `devops:www-data`.

## 5. Bước 2 - Phân quyền sở hữu và truy cập

### 5.1. Lệnh thực hiện

```
devops@halo:~$ sudo chown -R devops:www-data /opt/my-app
devops@halo:~$ sudo find /opt/my-app -type d -exec chmod 750 {} +
devops@halo:~$ sudo find /opt/my-app -type f -exec chmod 640 {} +
devops@halo:~$ sudo chmod 2770 /opt/my-app/logs
```

Phương án đã chọn cho thư mục logs: **2770** (`drwxrws---`), gồm quyền `rwx` cho owner và group, không có quyền cho other, kèm bit setgid. Phương án 2775 trong gợi ý của đề cũng hợp lệ; ở đây chọn 2770 theo nguyên tắc đặc quyền tối thiểu vì `/opt/my-app` (750) đã chặn other đi vào, nên bit `r-x` cho other trên `logs` vốn không có tác dụng thực tế.

### 5.2. Bảng quyền

| Đối tượng | Chủ sở hữu | Mode | Owner (devops) | Group (www-data) | Other |
|---|---|---|---|---|---|
| `/opt` | root:root | 755 | - | - | - |
| `/opt/my-app` | devops:www-data | 750 | rwx | r-x | --- |
| `/opt/my-app/html` | devops:www-data | 750 | rwx | r-x | --- |
| `/opt/my-app/html/*.html` | devops:www-data | 640 | rw- | r-- | --- |
| `/opt/my-app/logs` | devops:www-data | 2770 | rwx | rws (rwx + setgid) | --- |
| `/opt/my-app/logs/*.log` | www-data:www-data | 644 | (devops là other: r--) | rw- (www-data là owner) | r-- |

Ý nghĩa của r, w, x khác nhau giữa thư mục và tệp:

| Bit | Trên tệp | Trên thư mục |
|---|---|---|
| r (4) | Đọc nội dung tệp | Liệt kê tên các mục bên trong (`ls`) |
| w (2) | Sửa nội dung tệp | Tạo, xóa, đổi tên mục bên trong (cần kèm x) |
| x (1) | Thực thi tệp như chương trình | Đi vào (traverse) thư mục, truy cập mục bên trong khi biết tên |

Hệ quả cho Nginx: để phục vụ `/opt/my-app/html/index.html`, worker `www-data` cần bit `x` trên mọi thư mục dọc đường dẫn (`/`, `/opt`, `my-app`, `html`) và bit `r` trên chính tệp. Group `www-data` được cấp `r-x` trên thư mục web và `r--` trên tệp, đủ để đọc nhưng không thể sửa hay xóa mã nguồn. Ngược lại, thư mục `logs` cần `rwx` cho group vì Nginx và logrotate phải tạo, đổi tên, mở lại tệp log trong đó.

Bit setgid (số 2 đứng đầu trong `2770`) làm mọi tệp và thư mục tạo mới trong `logs` kế thừa group `www-data` của thư mục, thay vì group chính của người tạo. Nhờ đó file log mới luôn có group `www-data`.

### 5.3. Vì sao không dùng chmod 777

- Mọi tài khoản trên máy (kể cả tài khoản dịch vụ bị khai thác) đều ghi được, có thể chèn hoặc thay mã nguồn, xóa log để xóa dấu vết.
- Worker `www-data` tiếp xúc trực tiếp với Internet; nếu bị chiếm quyền thì không được phép sửa mã nguồn, vì thế `html` chỉ cấp `r-x` cho group.
- Quyền ghi chỉ mở đúng nơi cần (`logs`) cho đúng đối tượng (`www-data`); `777` xóa bỏ sự phân tách "devops ghi, www-data đọc" mà đề bài yêu cầu.

### 5.4. Kiểm chứng trạng thái phân quyền

```
devops@halo:~$ ls -la /opt/my-app/html/
total 16
drwxr-x--- 2 devops www-data 4096 Oct  2 10:07 .
drwxr-x--- 4 devops www-data 4096 Oct  2 15:06 ..
-rw-r----- 1 devops www-data 2036 Oct  2 10:07 404.html
-rw-r----- 1 devops www-data  623 Oct  1 15:03 index.html
devops@halo:~$ stat -c "%a %U:%G %n" /opt /opt/my-app /opt/my-app/html /opt/my-app/html/index.html /opt/my-app/html/404.html /opt/my-app/logs
755 root:root /opt
750 devops:www-data /opt/my-app
750 devops:www-data /opt/my-app/html
640 devops:www-data /opt/my-app/html/index.html
640 devops:www-data /opt/my-app/html/404.html
2770 devops:www-data /opt/my-app/logs
```

Chứng minh `www-data` đi qua được toàn bộ đường dẫn. Lưu ý `/opt` là `root:root` 755 nên mọi tài khoản đều có `x`; ba cấp còn lại cấp `x` cho group `www-data`:

```
devops@halo:~$ namei -l /opt/my-app/html/index.html
f: /opt/my-app/html/index.html
drwxr-xr-x root   root     /
drwxr-xr-x root   root     opt
drwxr-x--- devops www-data my-app
drwxr-x--- devops www-data html
-rw-r----- devops www-data index.html
```

Kiểm tra trực tiếp bằng chính tài khoản `www-data`:

```
devops@halo:~$ id www-data
uid=33(www-data) gid=33(www-data) groups=33(www-data)
devops@halo:~$ sudo -u www-data ls /opt/my-app/html
404.html  index.html
devops@halo:~$ sudo -u www-data test -r /opt/my-app/html/index.html && echo "www-data đọc được index.html"
www-data đọc được index.html
devops@halo:~$ sudo -u www-data touch /opt/my-app/html/x
touch: cannot touch '/opt/my-app/html/x': Permission denied
devops@halo:~$ sudo -u www-data touch /opt/my-app/logs/.write_test && ls -l /opt/my-app/logs/.write_test && sudo -u www-data rm /opt/my-app/logs/.write_test
-rw-r--r-- 1 www-data www-data 0 Oct  2 15:12 /opt/my-app/logs/.write_test
devops@halo:~$ touch /opt/my-app/logs/.setgid_test && ls -l /opt/my-app/logs/.setgid_test && rm /opt/my-app/logs/.setgid_test
-rw-rw-r-- 1 devops www-data 0 Oct  2 15:13 /opt/my-app/logs/.setgid_test
```

Kết quả: `www-data` đọc được mã nguồn, không ghi được vào `html`, ghi được vào `logs`. Tệp do `devops` tạo trong `logs` mang group `www-data` dù group chính của `devops` là `devops`, chứng tỏ setgid hoạt động.

## 6. Cách Nginx ghi log - vì sao thư mục logs vẫn cần quyền ghi cho www-data

Cần phân biệt chính xác hai tiến trình của Nginx:

1. **Master (chạy root)** đọc cấu hình và mở các file log khi khởi động hoặc `reload`. Vì chạy bằng root nên master luôn tạo được file mới trong `/opt/my-app/logs/`, kể cả khi `www-data` không có quyền gì trên thư mục này.
2. Sau khi mở file, master đổi chủ sở hữu file log sang user của worker (`www-data`). Việc này để worker có thể mở lại file khi nhận tín hiệu `USR1` (lệnh logrotate gửi sau khi đổi tên file log). Lệnh đổi chủ chỉ đặt user, giữ nguyên group; group của file lấy từ thư mục cha nhờ setgid.
3. **Worker (chạy www-data)** là tiến trình ghi từng dòng log trong lúc phục vụ yêu cầu, thông qua file descriptor đã được mở sẵn, và mở lại file khi nhận `USR1`.

Vì vậy quyền ghi của group `www-data` trên thư mục `logs` không cần cho lần tạo file đầu tiên (root làm được), nhưng vẫn cần thiết cho:

- Việc xoay vòng log: tạo file `access.log` mới sau khi đổi tên file cũ, nén, xóa bản cũ (thao tác trên thư mục cần `w`).
- Đúng yêu cầu của đề bài (group `www-data` có quyền ghi vào `/opt/my-app/logs/`).
- Các trường hợp vận hành khác như tạo file log phụ hoặc mở lại file khi file bị thay thế.

Kết quả thực tế sau khi `reload` (xem mục 8): `access.log` và `error.log` thuộc `www-data:www-data`, mode 644; group `www-data` có được nhờ bit setgid của thư mục.

## 7. Bước 3 - Server block Nginx

File `my-app.conf` (cùng thư mục với README này), cài vào `/etc/nginx/sites-available/my-app.conf`:

```nginx
# /etc/nginx/sites-available/my-app.conf
# Server block cho website tĩnh đặt tại /opt/my-app (môi trường Production).
# Site này thay thế vai trò của site my-web trên cổng 80.

server {
    # Lắng nghe cổng 80 cho IPv4 và IPv6.
    # default_server: nhận mọi yêu cầu không khớp server_name nào
    # (ví dụ truy cập trực tiếp bằng địa chỉ IP).
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Thư mục mã nguồn tĩnh, đã tách khỏi /var/www mặc định của hệ điều hành.
    root /opt/my-app/html;
    index index.html;

    # Log ghi trực tiếp vào thư mục logs riêng của dự án.
    # File log được tiến trình master (chạy root) mở khi start/reload,
    # sau đó chuyển chủ sở hữu sang www-data để worker mở lại được khi logrotate.
    access_log /opt/my-app/logs/access.log;
    error_log  /opt/my-app/logs/error.log warn;

    # Trang lỗi 404 tùy chỉnh; internal để không truy cập trực tiếp từ bên ngoài.
    error_page 404 /404.html;
    location = /404.html {
        internal;
    }

    # Chỉ phục vụ file tĩnh có thật, ngược lại trả 404.
    location / {
        try_files $uri $uri/ =404;
    }
}
```

Giải thích các chỉ thị chính:

| Chỉ thị | Ý nghĩa |
|---|---|
| `listen 80 default_server; listen [::]:80 default_server;` | Nhận kết nối IPv4 và IPv6 cổng 80, là server mặc định của cổng này |
| `server_name _;` | Tên giữ chỗ, không khớp tên miền thật nào, kết hợp `default_server` để bắt mọi yêu cầu |
| `root /opt/my-app/html;` | Gốc tài liệu nằm trong `/opt` |
| `access_log` / `error_log ... warn` | Ghi trực tiếp vào `/opt/my-app/logs/`; `error_log` chỉ ghi từ mức `warn` trở lên |
| `error_page 404 /404.html;` + `location = /404.html { internal; }` | Dùng trang 404 riêng, chỉ phục vụ khi Nginx tự chuyển hướng nội bộ |
| `try_files $uri $uri/ =404;` | Thử tệp, rồi thư mục, không có thì trả 404 |

Kích hoạt site, gỡ site cũ, kiểm tra cú pháp và nạp lại cấu hình:

```
devops@halo:~$ sudo ln -s /etc/nginx/sites-available/my-app.conf /etc/nginx/sites-enabled/my-app.conf
devops@halo:~$ sudo nginx -t
nginx: [emerg] a duplicate default server for 0.0.0.0:80 in /etc/nginx/sites-enabled/my-web.conf:3
nginx: configuration file /etc/nginx/nginx.conf test failed
devops@halo:~$ sudo rm /etc/nginx/sites-enabled/my-web.conf
devops@halo:~$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
devops@halo:~$ sudo systemctl reload nginx
```

Lần `nginx -t` đầu tiên báo lỗi là chủ đích của quy trình: hai site cùng khai báo `default_server` trên cổng 80 thì Nginx từ chối cấu hình. Sau khi gỡ symlink `my-web.conf` (chỉ xóa liên kết, file gốc trong `sites-available` còn nguyên) thì kiểm tra thành công và `reload` không làm gián đoạn kết nối đang phục vụ.

Trạng thái dịch vụ (`sudo systemctl status nginx --no-pager`, xem đầy đủ trong `terminal_log.txt`) là `active (running)`, lần reload lúc 15:18:12 kết thúc `status=0/SUCCESS`. Tiến trình sau khi reload:

```
devops@halo:~$ ps -eo user:8,pid,ppid,cmd | grep '[n]ginx'
root        1342       1 nginx: master process /usr/sbin/nginx -g daemon on; master_process on;
www-data   27518    1342 nginx: worker process
www-data   27519    1342 nginx: worker process
```

Master chạy `root`, hai worker chạy `www-data`, đúng mô hình đã phân tích ở mục 6.

## 8. Nginx tự tạo và ghi log tại đường dẫn mới

Gửi một yêu cầu nội bộ rồi xem thư mục logs:

```
devops@halo:~$ curl -sI http://127.0.0.1/ | head -n 1
HTTP/1.1 200 OK
devops@halo:~$ ls -la /opt/my-app/logs/
total 12
drwxrws--- 2 devops   www-data 4096 Oct  2 15:17 .
drwxr-x--- 4 devops   www-data 4096 Oct  2 15:06 ..
-rw-r--r-- 1 www-data www-data   84 Oct  2 15:19 access.log
-rw-r--r-- 1 www-data www-data    0 Oct  2 15:17 error.log
```

Hai tệp do Nginx tự tạo (không phải do `devops` tạo thủ công). Chúng thuộc `www-data:www-data`, mode 644: user `www-data` do master chuyển chủ sau khi mở, group `www-data` do thư mục `logs` có setgid. Mode 644 cho phép `devops` (không nằm trong group `www-data`, thuộc nhóm other của tệp) đọc log mà không cần `sudo`; việc `devops` duyệt được vào `logs` nhờ là owner của thư mục.

## 9. Kiểm tra theo đề bài

### 9.1. `ls -la /opt/my-app/`

```
devops@halo:~$ ls -la /opt/my-app/
total 16
drwxr-x--- 4 devops www-data 4096 Oct  2 15:06 .
drwxr-xr-x 3 root   root     4096 Oct  2 15:06 ..
drwxr-x--- 2 devops www-data 4096 Oct  2 10:07 html
drwxrws--- 2 devops www-data 4096 Oct  2 15:17 logs
```

Toàn bộ thuộc `devops:www-data`.

### 9.2. Ghi thử bằng devops, không dùng sudo

```
devops@halo:~$ echo "Update Test" >> /opt/my-app/html/index.html
devops@halo:~$ echo $?
0
devops@halo:~$ tail -n 2 /opt/my-app/html/index.html
</html>
Update Test
devops@halo:~$ ls -l /opt/my-app/html/index.html
-rw-r----- 1 devops www-data 635 Oct  2 15:25 /opt/my-app/html/index.html
```

Mã thoát `0`, nội dung đã được ghi, kích thước tăng từ 623 lên 635 byte (thêm 12 byte của "Update Test" và ký tự xuống dòng). Ngược lại, `www-data` không thể ghi vào tệp này:

```
devops@halo:~$ sudo -u www-data sh -c 'echo x >> /opt/my-app/html/index.html'
sh: 1: cannot create /opt/my-app/html/index.html: Permission denied
```

### 9.3. Truy cập từ máy cá nhân

```
$ curl -I http://103.116.104.228/
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Fri, 02 Oct 2026 08:27:02 GMT
Content-Type: text/html
Content-Length: 635
Last-Modified: Fri, 02 Oct 2026 08:25:37 GMT
Connection: keep-alive
ETag: "6abf6a81-27b"
Accept-Ranges: bytes

$ curl -s http://103.116.104.228/ | tail -n 2
</html>
Update Test
```

Trả về `200 OK`, không có 403. `Content-Length: 635` và `Last-Modified` khớp với tệp vừa sửa, nội dung "Update Test" xuất hiện trong phản hồi.

### 9.4. `tail -f /opt/my-app/logs/access.log`

```
devops@halo:~$ tail -f /opt/my-app/logs/access.log
127.0.0.1 - - [02/Oct/2026:15:19:20 +0700] "HEAD / HTTP/1.1" 200 0 "-" "curl/8.5.0"
113.161.72.19 - - [02/Oct/2026:15:27:02 +0700] "HEAD / HTTP/1.1" 200 0 "-" "curl/8.15.0"
113.161.72.19 - - [02/Oct/2026:15:27:31 +0700] "GET / HTTP/1.1" 200 635 "-" "curl/8.15.0"
```

Trong lúc `tail -f` đang chạy, gửi thêm hai yêu cầu từ máy cá nhân (một đường dẫn sai và một tệp có thật):

```
$ curl -s -o /dev/null -w "%{http_code} %{size_download}\n" http://103.116.104.228/khong-ton-tai
404 2036
$ curl -s -o /dev/null -w "%{http_code} %{size_download}\n" http://103.116.104.228/index.html
200 635
```

Cửa sổ `tail -f` hiển thị thêm ngay lập tức:

```
113.161.72.19 - - [02/Oct/2026:15:29:48 +0700] "GET /khong-ton-tai HTTP/1.1" 404 2036 "-" "curl/8.15.0"
113.161.72.19 - - [02/Oct/2026:15:30:05 +0700] "GET /index.html HTTP/1.1" 200 635 "-" "curl/8.15.0"
```

`devops` đọc được log không cần `sudo` vì file log mode 644 (other có quyền đọc) và `devops` là owner của thư mục `logs` nên duyệt vào được. Body 2036 byte của yêu cầu 404 chính là trang `404.html` tùy chỉnh.

### 9.5. error.log sau khi gọi đường dẫn sai

```
devops@halo:~$ sudo tail /opt/my-app/logs/error.log
devops@halo:~$ ls -l /opt/my-app/logs/error.log
-rw-r--r-- 1 www-data www-data 0 Oct  2 15:17 /opt/my-app/logs/error.log
```

`error.log` còn rỗng và đây là hành vi đúng: với `try_files $uri $uri/ =404`, việc tệp không tồn tại được xử lý như một kết quả hợp lệ (trả 404) chứ không phải lỗi, nên chỉ để lại dấu vết trong `access.log` (dòng 404 ở mục 9.4). `error.log` chỉ ghi các sự cố thực sự như lỗi quyền truy cập; dòng đầu tiên xuất hiện ở mục 10.

### 9.6. Log cũ không còn tăng

```
devops@halo:~$ ls -l /var/log/nginx/my-web.access.log
-rw-r----- 1 www-data adm 23417 Oct  2 14:52 /var/log/nginx/my-web.access.log
devops@halo:~$ sudo wc -l /var/log/nginx/my-web.access.log
176 /var/log/nginx/my-web.access.log
```

Chạy lại hai lệnh này sau toàn bộ các lần kiểm thử (khoảng 15:35) cho kết quả y hệt: 23417 byte, 176 dòng, thời điểm sửa cuối 14:52. Toàn bộ lưu lượng mới đã đi vào `/opt/my-app/logs/`.

## 10. Thử nghiệm phản chứng - vai trò của bit x trên group

Mục đích: chứng minh `www-data` đọc được web là nhờ bit `x` của group trên thư mục `html`, không phải do nguyên nhân khác. Tạm bỏ toàn bộ quyền của group (750 thành 700):

```
devops@halo:~$ chmod 700 /opt/my-app/html
devops@halo:~$ stat -c "%a %U:%G %n" /opt/my-app/html
700 devops:www-data /opt/my-app/html

$ curl -I http://103.116.104.228/
HTTP/1.1 403 Forbidden
Server: nginx/1.24.0 (Ubuntu)
Date: Fri, 02 Oct 2026 08:32:04 GMT
Content-Type: text/html
Content-Length: 162
Connection: keep-alive

devops@halo:~$ sudo tail -n 3 /opt/my-app/logs/error.log
2026/10/02 15:32:04 [error] 27519#27519: *6 "/opt/my-app/html/index.html" is forbidden (13: Permission denied), client: 113.161.72.19, server: _, request: "HEAD / HTTP/1.1", host: "103.116.104.228"
devops@halo:~$ tail -n 1 /opt/my-app/logs/access.log
113.161.72.19 - - [02/Oct/2026:15:32:04 +0700] "HEAD / HTTP/1.1" 403 0 "-" "curl/8.15.0"
```

Khôi phục về 750 thì website hoạt động lại:

```
devops@halo:~$ chmod 750 /opt/my-app/html
devops@halo:~$ stat -c "%a %U:%G %n" /opt/my-app/html
750 devops:www-data /opt/my-app/html

$ curl -I http://103.116.104.228/
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Fri, 02 Oct 2026 08:33:20 GMT
Content-Length: 635
```

Kết luận thử nghiệm:

| Trạng thái `html` | Quyền group `www-data` | HTTP | error.log |
|---|---|---|---|
| 750 | r-x | 200 OK | không có lỗi |
| 700 | --- | 403 Forbidden | `(13: Permission denied)` |
| 750 (khôi phục) | r-x | 200 OK | không phát sinh thêm |

Mã lỗi `13` là `EACCES`: tiến trình `www-data` bị hệ điều hành từ chối vì group `www-data` không còn bit `x` để đi vào thư mục. Thao tác `chmod` thực hiện bằng `devops` không cần `sudo` vì `devops` là owner của thư mục. Chính dòng log này cũng chứng minh `error_log` đang ghi đúng vào `/opt/my-app/logs/error.log`.

## 11. Bổ sung - logrotate cho /opt/my-app/logs

Vì log nằm ngoài `/var/log/nginx`, cấu hình logrotate có sẵn của gói `nginx` không bao phủ. File `my-app.logrotate` (cài vào `/etc/logrotate.d/my-app`, nội dung đầy đủ trong tệp và trong `terminal_log.txt`) gồm một khối cho `/opt/my-app/logs/*.log` với các chỉ thị sau:

| Chỉ thị | Tác dụng |
|---|---|
| `daily`, `rotate 14` | Xoay mỗi ngày, giữ 14 bản |
| `compress`, `delaycompress` | Nén bản cũ, hoãn nén một chu kỳ để Nginx kịp ghi nốt vào file vừa đổi tên |
| `create 0640 www-data www-data` | Tạo file log mới với chủ `www-data:www-data`, mode 640 |
| `postrotate ... kill -USR1` | Báo master Nginx mở lại file log; worker `www-data` mở được vì file mới thuộc `www-data` |
| `su www-data www-data` | Xoay vòng dưới user/group `www-data` |

Chạy thử (dry-run) lần đầu với bản chưa có chỉ thị `su` cho thấy lỗi thực tế do thư mục `logs` có quyền ghi theo group:

```
devops@halo:~$ sudo logrotate -d /etc/logrotate.d/my-app
...
considering log /opt/my-app/logs/access.log
error: skipping "/opt/my-app/logs/access.log" because parent directory has insecure permissions (It's world writable or writable by group which is not "root") Set "su" directive in config file to tell logrotate which user/group should be used for rotation.
...
```

Sau khi bổ sung `su www-data www-data` (bản cuối ở trên):

```
devops@halo:~$ sudo logrotate -d /etc/logrotate.d/my-app
rotating pattern: /opt/my-app/logs/*.log  after 1 days (14 rotations)
empty log files are not rotated, old logs are removed
switching euid to 33 and egid to 33
considering log /opt/my-app/logs/access.log
Creating new state
  Now: 2026-10-02 15:40
  Last rotated at 2026-10-02 15:00
  log does not need rotating (log has been rotated at 2026-10-2 15:0, that is not day ago yet)
considering log /opt/my-app/logs/error.log
Creating new state
  Now: 2026-10-02 15:40
  Last rotated at 2026-10-02 15:00
  log does not need rotating (log has been rotated at 2026-10-2 15:0, that is not day ago yet)
switching euid to 0 and egid to 0
```

Cấu hình hợp lệ: logrotate nhận diện hai file log, chưa xoay vì file mới được theo dõi lần đầu. Có thể xem kế hoạch xoay vòng đầy đủ (kể cả `postrotate`) bằng `sudo logrotate -d -f /etc/logrotate.d/my-app`.

Lưu ý quan trọng sau lần xoay vòng đầu tiên: file mới do logrotate tạo có mode 640 `www-data:www-data`, khi đó `devops` (không thuộc group `www-data`) không còn đọc được log bằng `tail` thường mà phải dùng `sudo tail`. Nếu muốn `devops` đọc không cần sudo, có thể đổi sang `create 0640 www-data devops`, hoặc thêm `devops` vào group `www-data`. Bài này giữ nguyên `0640 www-data www-data` theo thiết kế.

### AppArmor

Trên Ubuntu mặc định không có profile AppArmor nào giới hạn Nginx, nên việc ghi vào `/opt/my-app/logs/` và đọc `/opt/my-app/html/` không bị chặn bởi AppArmor:

```
devops@halo:~$ sudo aa-status 2>/dev/null | grep -i nginx || echo "Không có profile AppArmor nào cho nginx"
Không có profile AppArmor nào cho nginx
```

Nếu sau này triển khai profile AppArmor cho Nginx thì phải cho phép thêm hai đường dẫn `/opt/my-app/html/**` (đọc) và `/opt/my-app/logs/*` (ghi), nếu không sẽ gặp lỗi `Permission denied` dù quyền Unix đúng.

## 12. Script tự động hóa

File `setup_opt_webroot.sh` gom toàn bộ các bước trên, có thể chạy lại nhiều lần (idempotent):

- `set -euo pipefail`; tự chạy lại bằng `sudo` nếu chưa là root.
- Chỉ sao chép mã nguồn khi `/opt/my-app/html` còn trống, không ghi đè nội dung đã chỉnh sửa.
- `chown`, `find ... chmod 750/640` và `chmod 2770` cho `logs`. Phần `find` bỏ qua các file bên trong `logs`: nếu chạy lại script sau khi Nginx đã tạo log, `chown devops` hoặc `chmod 640` đè lên sẽ làm worker không mở lại được file log khi logrotate gửi `USR1`.
- Cài server block, gỡ symlink `my-web.conf`, chạy `nginx -t`; nếu lỗi thì quay lui symlink và dừng, chỉ `reload` khi kiểm tra thành công.
- Cài cấu hình logrotate.

```
cd homework/session_03/ex5
bash setup_opt_webroot.sh
```

## 13. Xử lý sự cố

| Hiện tượng | Nguyên nhân thường gặp | Cách kiểm tra và khắc phục |
|---|---|---|
| Trình duyệt/curl báo 403 Forbidden | Group `www-data` thiếu `x` trên một thư mục dọc đường dẫn, hoặc thiếu `r` trên tệp | `namei -l /opt/my-app/html/index.html`; `sudo chmod 750` cho thư mục, `640` cho tệp, `sudo chown -R devops:www-data /opt/my-app` |
| `error.log` có `(13: Permission denied)` | Nginx bị từ chối quyền ở bước duyệt thư mục hoặc mở tệp | Đọc đường dẫn trong dòng lỗi, kiểm tra từng cấp bằng `namei -l`; thử `sudo -u www-data ls <đường dẫn>` |
| `nginx -t` báo `duplicate default server` | Hai site cùng `default_server` trên cổng 80 | Gỡ symlink site cũ khỏi `sites-enabled` (`sudo rm /etc/nginx/sites-enabled/my-web.conf`) |
| `access.log` thuộc `root` thay vì `www-data` | Chưa `reload` sau `nginx -t`, hoặc chạy lại lệnh `chown` đè lên | `sudo systemctl reload nginx` để master chuyển chủ; không `chown -R` vào bên trong `logs` |
| Sau xoay vòng, `tail` log báo `Permission denied` | File mới tạo theo `create 0640 www-data www-data`, `devops` không thuộc group | Dùng `sudo tail`, hoặc đổi `create` / thêm `devops` vào group `www-data` |
| `logrotate` báo `insecure permissions` | Thư mục logs ghi được bởi group khác root nhưng thiếu `su` | Thêm `su www-data www-data` vào khối cấu hình |
| Website lỗi sau khi chuyển site | Cấu hình mới có vấn đề | Quay lui: `sudo ln -s /etc/nginx/sites-available/my-web.conf /etc/nginx/sites-enabled/`, gỡ `my-app.conf`, `nginx -t`, `reload` |

## 14. Bảng đối chiếu yêu cầu đề bài

| Yêu cầu | Cách thực hiện | Bằng chứng |
|---|---|---|
| Mã nguồn tại `/opt/my-app/html/` | `mkdir -p`, `cp -a` từ `/var/www/my-web/html/.` | Mục 4 |
| Sở hữu đệ quy `devops:www-data` | `chown -R devops:www-data /opt/my-app` | Mục 5.4, 9.1 |
| devops toàn quyền đọc/ghi (750 với thư mục, 640 với tệp) | `find -type d chmod 750`, `find -type f chmod 640` | Mục 5.4, 9.2 (`echo $?` = 0) |
| www-data đọc và thực thi trên thư mục web | Group `r-x` trên `html` (750), `r--` trên tệp | Mục 5.4 (`namei -l`, `sudo -u www-data`) |
| www-data ghi được vào logs | `logs` mode 2770, group `www-data` có `rwx` | Mục 5.4, 8 |
| Server block ghi log vào đường dẫn mới | `access_log`, `error_log` trỏ `/opt/my-app/logs/` | Mục 7, 9.4, 10 |
| Ghi thử bằng devops không sudo | `echo "Update Test" >> .../index.html` | Mục 9.2 |
| `tail -f access.log` sau khi truy cập | Theo dõi trực tiếp, thấy dòng mới | Mục 9.4 |
| Không 403, Nginx hoạt động bình thường | `curl -I` trả `200 OK` | Mục 9.3 |
| Nginx tự ghi log vào tệp chỉ định | `access.log`, `error.log` thuộc `www-data:www-data` | Mục 8, 10 |
| Bổ sung xoay vòng log | `/etc/logrotate.d/my-app`, `logrotate -d` | Mục 11 |

## 15. Kết luận

- Mã nguồn và logs của dự án đã được cô lập tại `/opt/my-app/` theo FHS, tách khỏi `/var/www` và `/var/log/nginx` mặc định, thuận tiện sao lưu hoặc mount phân vùng riêng.
- Mô hình phân quyền phân tách vai trò rõ ràng: `devops` sở hữu và ghi mã nguồn không cần `sudo`; `www-data` chỉ đọc mã nguồn (`750`/`640`) và chỉ được ghi ở `logs` (`2770` kèm setgid), không dùng `777`.
- Nginx hoạt động bình thường với `200 OK`, tự tạo và ghi `access.log`, `error.log` tại đường dẫn mới. Master (root) mở file log rồi chuyển chủ sang `www-data`; quyền ghi của group trên thư mục `logs` phục vụ việc xoay vòng và đúng yêu cầu đề.
- Thử nghiệm `chmod 700` làm xuất hiện `403` và `(13: Permission denied)`, khôi phục `750` thì hết lỗi, chứng minh bit `x` của group `www-data` là điều kiện để Nginx đi qua thư mục web.
