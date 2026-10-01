# DevOps - Session 03 - Bài 5: Thiết lập thư mục Web an toàn tại /opt/

Chuyển website tĩnh và logs của Nginx ra khỏi đường dẫn mặc định sang `/opt/my-app/` để cô lập mã nguồn, đồng thời phân quyền để tách vai trò giữa tài khoản quản trị `devops` và tiến trình Nginx `www-data`:

- Mã nguồn tại `/opt/my-app/html/`, logs tại `/opt/my-app/logs/`.
- Sở hữu đệ quy `devops:www-data`; thư mục 750, tệp 640, thư mục logs 2770 (setgid).
- Server block Nginx ghi `access_log` và `error_log` trực tiếp vào `/opt/my-app/logs/`.
- Bổ sung logrotate, script tự động hóa idempotent và bảng xử lý sự cố.

## Mục lục

- Báo cáo chi tiết: [homework/session_03/ex5/README.md](homework/session_03/ex5/README.md)
  1. Mục tiêu và bối cảnh
  2. Môi trường thực hiện
  3. Vì sao dùng /opt theo chuẩn FHS
  4. Tạo cấu trúc và sao chép mã nguồn
  5. Phân quyền sở hữu và truy cập
  6. Cách Nginx ghi log
  7. Server block Nginx
  8. Nginx tự tạo và ghi log tại đường dẫn mới
  9. Kiểm tra theo đề bài
  10. Thử nghiệm phản chứng
  11. Bổ sung logrotate và AppArmor
  12. Script tự động hóa
  13. Xử lý sự cố
  14. Bảng đối chiếu yêu cầu đề bài
  15. Kết luận

## Danh sách tệp

```
homework/session_03/ex5/
|-- README.md               Báo cáo chi tiết
|-- my-app.conf             Server block Nginx
|-- terminal_log.txt        Log Terminal đầy đủ
|-- setup_opt_webroot.sh    Script bash tự động hóa (idempotent)
+-- my-app.logrotate        Cấu hình logrotate
```
