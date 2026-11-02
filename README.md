# App kho Tuibao

Đây là app mới dựa trên prototype, ưu tiên dùng trên điện thoại. App dùng chung dữ liệu qua Supabase và cập nhật realtime.

## Có những chức năng gì?

- Nhân viên đăng nhập, chỉ xem kho chi nhánh được giao và chỉ nhập/xuất.
- Quản lý tạo tài khoản nhân viên, quản lý nguyên liệu và chi nhánh.
- Chỉ quản lý được điều chỉnh số lượng và chuyển nguyên liệu giữa các chi nhánh.
- Xem lịch sử xuất kho theo ngày, tuần, tháng, năm và số liệu theo tháng.
- Thêm ảnh nguyên liệu.
- Nhân viên tự đổi mật khẩu và cập nhật ảnh đại diện; quản lý có thể gắn ảnh cho nhân viên.

## Cài dữ liệu vào Supabase

1. Mở dự án Supabase **quan ly kho 2.0**.
2. Chọn **SQL Editor → New query**.
3. Mở tệp `supabase/migrations/0001_inventory.sql`, sao chép toàn bộ nội dung vào ô SQL Editor rồi bấm **Run**. Tệp này tạo các bảng và quyền truy cập cho app; không xóa bảng hay dữ liệu hiện có. Đọc lại trước khi chạy.
4. Chọn **Authentication → Users → Add user**. Tạo tài khoản quản lý với email `quanly01@tuibao.invalid`, nhập mật khẩu mới và bật xác nhận email nếu Supabase hỏi.
5. Vào lại **SQL Editor → New query**, mở `supabase/bootstrap_manager.sql`, sao chép nội dung vào rồi bấm **Run**. Bước này gán quyền quản lý cho tài khoản vừa tạo.

## Cài chức năng tạo tài khoản nhân viên

App tạo tài khoản nhân viên bằng một hàm bảo mật phía Supabase. Hàm này cần được triển khai trong **Edge Functions** và cài một khóa bí mật ở phía Supabase. Khóa bí mật không được nhập vào app hoặc gửi trong chat. Tệp hàm nằm tại `supabase/functions/create-staff/index.ts`.

## Bật ảnh đại diện

Sau khi đã chạy migration `0001_inventory.sql`, chạy thêm `supabase/migrations/0002_staff_avatars.sql` trong **SQL Editor**. Migration này chỉ thêm cột ảnh đại diện, bucket lưu ảnh riêng tư và quyền đọc/tải ảnh; không xóa dữ liệu kho. Đổi mật khẩu của chính tài khoản không cần migration.

## Đưa app lên mạng

Tệp giao diện nằm trong thư mục `public`. Đưa toàn bộ thư mục này lên dịch vụ lưu trữ website (ví dụ Vercel) để có đường link cho nhân viên mở trên điện thoại. Tài khoản Vercel hiện chưa được kết nối trong phiên này, nên app chưa được xuất bản.

## Ghi chú an toàn

- `public/config.js` chỉ chứa địa chỉ Supabase và khóa publishable dùng cho giao diện web. Quyền truy cập dữ liệu được giới hạn bằng chính sách cơ sở dữ liệu.
- Không đưa khóa Secret / service-role vào thư mục `public`, không gửi khóa đó trong chat.
- Nguyên liệu và chi nhánh được lưu trữ thay vì xóa vĩnh viễn để giữ lịch sử giao dịch.
- Mật khẩu quản lý không được lưu trong bộ app.

