# Sushi Platform

Nền tảng quản lý vận hành chuỗi nhà hàng Sushi, gồm website đặt món mang
đi, trang quản trị và backend NestJS theo kiến trúc **microservices**.
Các service giao tiếp đồng bộ qua HTTP khi cần phản hồi tức thì, và bất
đồng bộ qua RabbitMQ cho domain event/tác vụ nền. Mỗi service sở hữu dữ
liệu của mình; PostgreSQL là hệ quản trị dữ liệu, Redis phục vụ cache và
các nhu cầu dữ liệu tạm thời phù hợp. Ứng dụng di động là client riêng
dự kiến cho giai đoạn sau.

> **Trạng thái:** Tài liệu mô tả kiến trúc mục tiêu và quy ước phát
> triển. Các app, package, script và service chỉ được xem là đã triển
> khai khi chúng thực sự tồn tại trong repository.

## Mục lục

-   [1. Mục tiêu dự án](#1-mục-tiêu-dự-án)
-   [2. Phạm vi MVP](#2-phạm-vi-mvp)
-   [3. Công nghệ](#3-công-nghệ)
-   [4. Kiến trúc tổng thể](#4-kiến-trúc-tổng-thể)
-   [5. Cấu trúc repository](#5-cấu-trúc-repository)
-   [6. Trách nhiệm các ứng dụng và
    module](#6-trách-nhiệm-các-ứng-dụng-và-module)
-   [7. Giao tiếp giữa các thành phần](#7-giao-tiếp-giữa-các-thành-phần)
-   [8. Quy tắc dữ liệu và tồn kho](#8-quy-tắc-dữ-liệu-và-tồn-kho)
-   [9. Cơ sở dữ liệu](#9-cơ-sở-dữ-liệu)
-   [10. Cấu hình môi trường](#10-cấu-hình-môi-trường)
-   [11. Khởi chạy môi trường local](#11-khởi-chạy-môi-trường-local)
-   [12. Quy ước phát triển](#12-quy-ước-phát-triển)
-   [13. Kiểm thử và chất lượng](#13-kiểm-thử-và-chất-lượng)
-   [14. Bảo mật](#14-bảo-mật)
-   [15. Lộ trình dự kiến](#15-lộ-trình-dự-kiến)

## 1. Mục tiêu dự án

Xây dựng một nền tảng có thể bắt đầu từ một cửa hàng và mở rộng lên
nhiều chi nhánh, kho hàng, người dùng và kênh bán hàng mà không phải
thiết kế lại toàn bộ hệ thống.

Các mục tiêu chính:

-   Quản lý thực đơn, sản phẩm đơn và combo.
-   Nhận đơn Take Away trực tuyến và theo dõi trạng thái đơn.
-   Quản lý nguyên liệu, đơn vị tính, công thức và định mức.
-   Quản lý nhập hàng, điều chỉnh kho, kiểm kê và lịch sử biến động tồn.
-   Tự động ghi nhận lượng nguyên liệu tiêu hao theo công thức khi đơn
    chuyển sang trạng thái được quy định.
-   Theo dõi thanh toán và các giao dịch tiền.
-   Phân quyền người dùng theo vai trò và phạm vi chi nhánh/kho.
-   Tạo nền tảng để bổ sung POS, thanh toán trực tuyến, mã vạch và ứng
    dụng di động trong các giai đoạn sau.

## 2. Phạm vi MVP

### Storefront

-   Hiển thị danh mục và thực đơn.
-   Xem thông tin, giá bán và tùy chọn sản phẩm.
-   Thêm/xóa/cập nhật giỏ hàng.
-   Tạo đơn Take Away và chọn khung giờ nhận hàng nếu được bật.
-   Xem trạng thái đơn hàng.
-   Không tin tưởng giá, tổng tiền hoặc trạng thái do trình duyệt gửi
    lên; backend phải tính và xác thực lại.

### Admin Web

-   Đăng nhập và phân quyền.
-   Quản lý sản phẩm, danh mục, combo và giá bán.
-   Quản lý nguyên liệu, đơn vị tính, quy đổi đơn vị và công thức món.
-   Quản lý nhà cung cấp và phiếu nhập hàng.
-   Theo dõi tồn kho, lịch sử nhập/xuất/điều chỉnh và kiểm kê.
-   Quản lý đơn hàng và trạng thái xử lý.
-   Xem báo cáo doanh thu và tồn kho cơ bản.

### Inventory

-   Theo dõi tồn theo từng kho và nguyên liệu.
-   Ghi nhận phiếu nhập, điều chỉnh, kiểm kê và tiêu hao do bán hàng.
-   Lưu lịch sử biến động kho để truy vết.
-   Hỗ trợ quy trình ghi nhận lượng sử dụng thực tế sau khi chế biến,
    nếu cần.
-   Chặn hoặc cảnh báo tồn âm theo chính sách được cấu hình.

### Ngoài phạm vi MVP mặc định

Các tính năng dưới đây có thể được bổ sung sau khi nghiệp vụ và nhà cung
cấp được xác định:

-   POS tại quầy.
-   Tích hợp cổng thanh toán trực tuyến.
-   Quét mã vạch.
-   Ứng dụng di động cho nhân viên bếp/nhân viên kho.
-   Dự báo nhu cầu, loyalty và báo cáo nâng cao.

## 3. Công nghệ

  -----------------------------------------------------------------------
  Thành phần              Công nghệ định hướng    Vai trò
  ----------------------- ----------------------- -----------------------
  Monorepo                pnpm Workspaces         Quản lý nhiều app và
                                                  package trong một
                                                  repository

  Admin Web               Next.js, TypeScript     Giao diện quản trị

  Storefront              Next.js, TypeScript     Website khách hàng

  Mobile                  Expo, React Native,     Ứng dụng di động ở giai
                          TypeScript              đoạn sau

  Backend                 NestJS                  Các service độc lập theo
                                                  bounded context

  Giao tiếp service       REST/HTTP và RabbitMQ   HTTP cho request cần phản
                                                  hồi; RabbitMQ cho event
                                                  và xử lý bất đồng bộ

  Database                PostgreSQL              Nguồn dữ liệu nghiệp vụ
                                                  chính

  ORM                     Prisma                  Truy cập và quản lý
                                                  schema database

  Message broker          RabbitMQ                Domain event, command,
                                                  retry và dead-letter queue

  Cache / ephemeral data  Redis                   Cache, rate limiting,
                                                  session hoặc dữ liệu tạm

  Background jobs         BullMQ (tùy nhu cầu)    Tác vụ nền cần retry,
                                                  lịch chạy hoặc xử lý lâu

  API documentation       OpenAPI/Swagger         Tài liệu hóa REST API

  Validation              class-validator hoặc    Kiểm tra dữ liệu đầu
                          giải pháp thống nhất    vào
                          của dự án

  Local infrastructure    Docker Compose          Chạy PostgreSQL, Redis,
                                                  RabbitMQ và các service
  -----------------------------------------------------------------------

Phiên bản cụ thể của Node.js, pnpm, NestJS, Prisma và các package phải
được cố định trong cấu hình repository. Không nên coi các phiên bản
trong tài liệu này là phiên bản đã được cài đặt.

## 4. Kiến trúc tổng thể

``` text
Clients: Storefront / Admin / Mobile (giai đoạn sau)
                         │ HTTPS / REST
                  ┌──────▼──────┐
                  │ API Gateway │
                  └──────┬──────┘
                         │ REST tới các service
      ┌──────────────────┼──────────────────────────────────┐
      │                  │                 │                │
┌─────▼─────┐  ┌────────▼───┐  ┌──────────▼─┐  ┌───────────▼──┐
│ Identity  │  │ Catalog    │  │ Ordering   │  │ Inventory    │
│ Service   │  │ Service    │  │ Service    │  │ Service      │
└─────┬─────┘  └─────┬──────┘  └──────┬─────┘  └──────┬───────┘
      │              │                │               │
      └──────────────┴────────────────┴───────────────┐
                                                      │
      ┌─────────────────────┐   ┌────────────────────┤
      │ Purchasing Service  │   │ Finance Service    │
      └──────────┬──────────┘   └──────────┬─────────┘
                 └──────────────┬──────────┘
                                ▼
                  PostgreSQL database sushi_platform
                  (schema riêng cho từng service)

       Services ⇄ RabbitMQ (events, commands, retries/DLQ)
       Redis: cache / session / rate limit / dữ liệu tạm
```

Đây là kiến trúc đích, không phải mô tả những thành phần đã được triển
khai trong repository. API Gateway định tuyến HTTP tới tất cả service;
RabbitMQ mang event/command bất đồng bộ giữa chúng. Các service là process
độc lập nhưng trước mắt dùng chung database `sushi_platform`, với schema,
quyền truy cập và migration được phân chia theo service. Redis không thay
thế database hay RabbitMQ.

### Nguyên tắc kiến trúc

-   Mỗi service sở hữu schema, migration và quy tắc nghiệp vụ của mình;
    service khác không ghi trực tiếp vào các bảng đó. Cấp database role
    riêng để giới hạn quyền.
-   Dùng REST/HTTP cho truy vấn hoặc lệnh cần phản hồi ngay; RabbitMQ
    cho domain event và command bất đồng bộ giữa các bounded context.
-   Mọi consumer phải idempotent. Ghi thay đổi nghiệp vụ và outbox trong
    cùng transaction; dùng inbox/deduplication khi nhận message.
-   Giao dịch nội bộ một service phải nguyên tử. Luồng nhiều service dùng
    saga, event kết quả và thao tác bù khi nghiệp vụ yêu cầu; không giả định
    có distributed transaction.
-   Redis dùng cho dữ liệu có thể tạo lại hoặc dữ liệu tạm; không dùng làm
    nguồn dữ liệu chuẩn cho đơn hàng, thanh toán hay tồn kho.
-   Đo lường queue, retry, DLQ, độ trễ và health của từng service.

## 5. Cấu trúc repository

Định hướng **monorepo thuần với pnpm Workspaces**, không dùng Git
submodule cho các app nằm trong repository này.

``` text
sushi-platform/
├── apps/
│   ├── admin-web/                 # Next.js admin
│   ├── storefront/                # Next.js customer website
│   ├── mobile/                    # Expo app, triển khai sau
│   ├── api-gateway/               # Public REST entry point
│   ├── identity-service/          # Users, roles, permissions
│   ├── catalog-service/           # Products, combos, recipes
│   ├── ordering-service/          # Orders and order lifecycle
│   ├── inventory-service/         # Warehouses, stock ledger, usage
│   ├── purchasing-service/        # Suppliers and purchase receipts
│   └── finance-service/           # Payments and cash transactions
├── packages/
│   ├── config/                    # Shared lint/TypeScript config
│   └── contracts/                 # Versioned event contracts
├── infrastructure/
│   └── docker/
│       └── docker-compose.yml
├── docs/
│   ├── architecture/
│   ├── database/
│   ├── api/
│   └── decisions/
├── .env.example
├── .gitignore
├── package.json
├── pnpm-workspace.yaml
├── README.md
└── tsconfig.base.json
```

Cấu trúc trên là cấu trúc mục tiêu, chưa phản ánh các thư mục hiện có.
Mỗi service có package, cấu hình, migration và vòng đời triển khai riêng.
Package `contracts` chỉ chứa message/API contract ổn định, không chứa
logic nghiệp vụ hoặc model database dùng chung. Có thể bổ sung
notification-service khi cần gửi email/SMS/push.

## 6. Trách nhiệm các ứng dụng và service

  -----------------------------------------------------------------------
  Ứng dụng/service                    Trách nhiệm chính
  ----------------------------------- -----------------------------------
  `admin-web`                         Giao diện vận hành cho quản lý,
                                      nhân viên và nhân viên kho

  `storefront`                        Thực đơn, giỏ hàng, đặt món và theo
                                      dõi đơn

  `mobile`                            Ứng dụng nhân viên/bếp/kho ở giai
                                      đoạn sau

  `api-gateway`                       Điểm vào công khai, xác thực token,
                                      rate limiting và định tuyến HTTP;
                                      không chứa quy tắc nghiệp vụ

  `identity-service`                  Người dùng, vai trò, quyền, chi
                                      nhánh và phạm vi truy cập; phát
                                      hành/kiểm tra danh tính

  `catalog-service`                   Danh mục, sản phẩm, combo và công
                                      thức; phát event khi dữ liệu được
                                      công bố/cập nhật

  `ordering-service`                  Đơn hàng, snapshot tên/giá sản phẩm,
                                      lịch sử trạng thái và điều phối saga

  `inventory-service`                 Nguyên liệu/kho theo ERD đã chốt,
                                      số dư, stock ledger, kiểm kê và
                                      tiêu hao; là nơi duy nhất ghi tồn

  `purchasing-service`                Nhà cung cấp, phiếu nhập; yêu cầu
                                      Inventory ghi nhận nhập kho qua event

  `finance-service`                   Thanh toán khách hàng/nhà cung cấp,
                                      cash accounts và cash transactions
  -----------------------------------------------------------------------

Mỗi service chỉ ghi database do mình sở hữu. Tên ID từ service khác có
thể được lưu làm tham chiếu, nhưng không tạo khóa ngoại xuyên database;
thông tin cần thiết để hiển thị hoặc xử lý được lưu thành snapshot hay
projection qua API/event. Các phân vùng dữ liệu cuối cùng cần được chốt
trước khi triển khai migration.

## 7. Giao tiếp giữa các thành phần

### REST/HTTP

-   Frontend gọi API Gateway qua HTTPS/REST; gateway định tuyến tới
    service phù hợp.
-   Dùng REST cho thao tác cần phản hồi ngay, ví dụ xem thực đơn, tạo
    đơn hoặc truy vấn trạng thái.
-   Tài liệu hóa endpoint bằng OpenAPI/Swagger.
-   API phải xác thực và phân quyền ở backend; ẩn nút trên frontend
    không được xem là cơ chế bảo mật.

### RabbitMQ và domain event

RabbitMQ là message broker giữa các service. Service phát event sau khi
ghi dữ liệu của mình; consumer cập nhật dữ liệu riêng và không truy cập
database của producer. Event contract có version, event ID, thời điểm,
correlation/causation ID và payload tối thiểu cần thiết. Dùng exchange,
queue riêng theo consumer, retry giới hạn và dead-letter queue.

Service gọi HTTP trực tiếp tới service sở hữu dữ liệu khi cần câu trả lời
đồng bộ; ví dụ Ordering kiểm tra sản phẩm và lấy giá từ Catalog khi tạo
đơn, rồi lưu snapshot tên/giá vào đơn. Đặt timeout và giới hạn retry cho
các lời gọi liên service. Không dùng API Gateway để service-to-service
call và không truy cập database của service khác.

Luồng tồn kho khi bắt đầu chế biến là saga: Ordering ghi yêu cầu bắt đầu
chế biến và outbox trong transaction, rồi phát command/event. Inventory
xử lý idempotent trong transaction của mình, ghi usage/document/movement
và cập nhật balance cùng nhau, sau đó trả event thành công hoặc thất bại.
Ordering chỉ chuyển đơn sang `PREPARING` khi nhận kết quả thành công.
Nếu thất bại, giữ đơn ở trạng thái chờ/xử lý lỗi theo chính sách; nếu cần
hủy sau khi đã trừ kho, phát yêu cầu bù bằng chứng từ đảo/điều chỉnh, không
sửa lịch sử movement.

Mỗi service dùng Transactional Outbox để tránh mất event giữa database
commit và publish. Consumer dùng inbox hoặc khóa idempotency để xử lý
message giao lại an toàn.

### Redis

Dùng Redis cho cache dữ liệu catalog, session/token tùy mô hình xác thực,
rate limiting hoặc dữ liệu tạm có TTL. Có thể dùng Redis với BullMQ cho
job nền riêng; RabbitMQ vẫn là kênh tích hợp domain giữa microservice.
Redis không phải nguồn dữ liệu chuẩn cho đơn hàng, thanh toán hoặc tồn
kho. Cache cần TTL/invalidation rõ ràng và phải có thể dựng lại từ nguồn
dữ liệu sở hữu.

## 8. Quy tắc dữ liệu và tồn kho

### Tồn kho và sổ biến động

-   `stock_balances` lưu số lượng tồn hiện tại theo `warehouse_id` và
    `ingredient_id`.
-   `stock_movements` là sổ ghi nhận biến động kho; không sửa/xóa lịch
    sử đã ghi nhận để "sửa cho khớp".
-   Điều chỉnh sai lệch bằng một giao dịch điều chỉnh mới có lý do,
    người thực hiện và thời gian.
-   Cập nhật `stock_balances` và ghi `stock_movements` trong cùng một
    transaction database.
-   Mọi thao tác nhập/xuất/điều chỉnh phải có mã tham chiếu nghiệp vụ và
    khóa chống xử lý lặp phù hợp.

### Công thức và tiêu hao nguyên liệu

-   Công thức quy định định mức nguyên liệu cho một đơn vị sản phẩm.
-   Khi đơn chuyển sang trạng thái được cấu hình để bắt đầu chế biến, hệ
    thống ghi nhận tiêu hao theo công thức.
-   Phải xác định rõ một trạng thái duy nhất kích hoạt trừ kho và ngăn
    việc chuyển trạng thái/lặp event làm trừ kho nhiều lần.
-   Nếu cần ghi nhận lượng sử dụng thực tế, lưu chênh lệch/điều chỉnh có
    lý do; không trừ lại toàn bộ định mức một lần nữa.
-   Với combo, mở rộng combo thành các sản phẩm con rồi tính tiêu hao
    theo công thức của từng sản phẩm con; không trừ cả combo và các
    thành phần cùng lúc.
-   Xây dựng chính sách tồn âm rõ ràng: chặn đơn, cảnh báo hoặc cho phép
    theo quyền. Không để hành vi mặc định quyết định nghiệp vụ.
-   Việc hoàn/hủy đơn sau khi đã tiêu hao cần quy tắc riêng; không tự
    động cộng trả nguyên liệu nếu thực tế nguyên liệu đã được sử dụng.

### Nhập hàng và giá vốn

-   Phiếu nhập hàng và thanh toán nhà cung cấp là hai nghiệp vụ khác
    nhau.
-   Ghi nhận nhập kho không đồng nghĩa với việc khoản thanh toán đã được
    thực hiện.
-   Nếu dùng giá vốn bình quân gia quyền, xác định rõ phạm vi tính (theo
    kho/nguyên liệu), cách xử lý nhập trả, điều chỉnh, hàng hỏng và làm
    tròn.
-   Dùng kiểu số thập phân phù hợp cho số lượng, đơn giá và tiền; tránh
    dùng floating point cho phép tính tiền.
-   Lưu đơn vị cơ sở cho nguyên liệu và quản lý quy đổi đơn vị một cách
    nhất quán.

### Đơn hàng và thanh toán

-   Backend tự tính lại giá, giảm giá, phí và tổng tiền.
-   Lưu lịch sử trạng thái đơn.
-   Tách đơn hàng, thanh toán của khách và sổ giao dịch tiền.
-   Callback/webhook thanh toán (khi tích hợp) phải được xác thực và xử
    lý idempotent.
-   Không đánh dấu thanh toán thành công chỉ dựa vào dữ liệu do frontend
    gửi lên.

### Nhiều chi nhánh và kho

-   Thiết kế `branch_id` và `warehouse_id` ngay từ đầu dù MVP chỉ có một
    chi nhánh.
-   Mỗi request phải kiểm tra người dùng có quyền truy cập chi nhánh/kho
    được yêu cầu hay không.
-   Không dựa vào giá trị `branch_id` do client gửi lên mà không xác
    thực quyền.
-   Tách dữ liệu tồn theo kho; việc chuyển kho cần chứng từ và hai phía
    xuất/nhập có thể truy vết.

## 9. Cơ sở dữ liệu

### Nguyên tắc

Trước mắt dùng **một database PostgreSQL cho mỗi môi trường** (local,
staging, production). Tổ chức bảng theo schema của service, ví dụ
`identity`, `catalog`, `ordering`, `inventory`, `purchasing`, `finance`.
Cấp database role riêng cho từng service và chỉ cho phép quyền cần thiết
trên schema/bảng mà service sở hữu. Không tạo database riêng cho từng
frontend.

Ranh giới sở hữu dự kiến:

-   Identity: `users`, `roles`, `permissions`, `user_roles`,
    `role_permissions` và `branches`.
-   Catalog: danh mục, sản phẩm, combo, nguyên liệu, đơn vị và công thức.
-   Ordering: khách hàng, đơn hàng, dòng hàng snapshot và lịch sử trạng thái.
-   Inventory: `warehouses`, số dư, chứng từ, stock movements, kiểm kê,
    preparation usage và điều chỉnh tiêu hao. Recipe/ingredient cần thiết
    được nhận thành projection từ Catalog.
-   Purchasing: nhà cung cấp, phiếu nhập và dòng phiếu nhập.
-   Finance: thanh toán đơn hàng/nhà cung cấp, tài khoản tiền và giao dịch
    tiền. Ordering/Purchasing nhận trạng thái thanh toán qua event hoặc
    projection, không sở hữu bản ghi thanh toán.

ERD hiện tại là mô hình nghiệp vụ tổng hợp. Trước khi tạo migration, cần
đánh dấu rõ bảng nào thuộc service/schema nào. Dù các schema nằm trong
cùng database, tránh khóa ngoại và truy vấn ghi trực tiếp xuyên ranh giới
service để có thể tách database sau này. Giữa service dùng ID tham chiếu,
snapshot hoặc projection qua API/event. Các bảng đang chứa dữ liệu của
nhiều bounded context (ví dụ ingredients, recipes, preparation usage và
payment) cần được phân quyền sở hữu rõ.

### Nhóm thực thể dự kiến

Tên bảng cuối cùng cần được chuẩn hóa trong ERD và Prisma schema. Các
nhóm nghiệp vụ dự kiến gồm:

-   Identity: `users`, `roles`, `permissions`, bảng liên kết
    user-role/role-permission.
-   Organization: `branches` (Identity), `warehouses` (Inventory).
-   Catalog: `product_categories`, `products`, `combo_items`,
    `ingredients`, `units`, `unit_conversions`, `recipes`,
    `recipe_items`.
-   Purchasing: `suppliers`, `purchase_receipts`,
    `purchase_receipt_items`.
-   Ordering: `customers`, `orders`, `order_items`,
    `order_status_histories`.
-   Inventory: `stock_balances`, `stock_documents`,
    `stock_document_items`, `stock_movements`, `stock_counts`,
    `stock_count_items`, `preparation_runs`, `order_ingredient_usages`,
    `ingredient_usage_adjustments`.
-   Finance: `order_payments`, `supplier_payments`, `cash_accounts`,
    `cash_transactions`.
-   Reliability: bảng outbox/inbox và/hoặc idempotency thuộc schema của
    từng service theo thiết kế.

Đây là danh sách thực thể nghiệp vụ tổng hợp, không phải migration đã
được tạo. Mỗi service có migration riêng cho schema mình sở hữu; outbox
và inbox cũng nằm trong schema đó. Cần chốt quyền sở hữu bảng, khóa ngoại
nội bộ, unique constraints, indexes và chính sách xóa trước khi phát triển.
Hiện chưa cần quyết định thời điểm tách thành nhiều database; chỉ xem xét
việc đó khi yêu cầu scale, bảo mật hoặc triển khai độc lập thực sự xuất hiện.

## 10. Cấu hình môi trường

Tạo file `.env` ở local dựa trên `.env.example`. Không commit `.env`
hoặc credential thật lên Git.

Ví dụ các biến môi trường:

``` dotenv
NODE_ENV=development

POSTGRES_DB=sushi_platform
# Tài khoản bootstrap local, không dùng làm credential runtime
POSTGRES_USER=sushi_app
POSTGRES_PASSWORD=change_me_local
POSTGRES_PORT=5432

REDIS_PORT=6379
RABBITMQ_DEFAULT_USER=sushi_app
RABBITMQ_DEFAULT_PASS=change_me_local
RABBITMQ_PORT=5672
RABBITMQ_MANAGEMENT_PORT=15672

# Cùng một database, user riêng cho schema của mỗi service.
IDENTITY_DATABASE_URL=postgresql://identity_app:change_me_local@localhost:5432/sushi_platform
CATALOG_DATABASE_URL=postgresql://catalog_app:change_me_local@localhost:5432/sushi_platform
ORDERING_DATABASE_URL=postgresql://ordering_app:change_me_local@localhost:5432/sushi_platform
INVENTORY_DATABASE_URL=postgresql://inventory_app:change_me_local@localhost:5432/sushi_platform
PURCHASING_DATABASE_URL=postgresql://purchasing_app:change_me_local@localhost:5432/sushi_platform
FINANCE_DATABASE_URL=postgresql://finance_app:change_me_local@localhost:5432/sushi_platform
RABBITMQ_URL=amqp://sushi_app:change_me_local@localhost:5672
REDIS_URL=redis://localhost:6379
```

Lưu ý:

-   Đây là giá trị local minh họa, không dùng mật khẩu này ở
    staging/production.
-   Khi chạy app bên trong Docker Compose, hostname thường là tên
    service, ví dụ `postgres`, `rabbitmq` hoặc `redis`, không phải
    `localhost`.
-   PostgreSQL local dùng một database `sushi_platform`; cần tạo schema
    và role riêng cho mỗi service. Không dùng bootstrap/superuser làm
    credential runtime.
-   Các biến trong `.env.example` phải được đồng bộ với cấu hình thực tế
    của từng app.
-   Nếu URL chứa ký tự đặc biệt trong username/password, cần URL-encode
    đúng cách.
-   Không đưa secret vào frontend bundle hoặc commit secret vào
    repository.

## 11. Khởi chạy môi trường local

### Yêu cầu

-   Git.
-   Node.js phiên bản LTS được dự án quy định.
-   Corepack hoặc pnpm đúng phiên bản trong `packageManager`.
-   Docker Desktop hoặc Docker Engine có Docker Compose.
-   Các biến môi trường local đã được cấu hình.

### Bước 1: Clone repository

``` bash
git clone <REPOSITORY_URL> sushi-platform
cd sushi-platform
```

Thay `<REPOSITORY_URL>` bằng URL repository thực tế.

### Bước 2: Cài dependencies

``` bash
corepack enable
pnpm install
```

Lệnh này chỉ hoạt động khi đã có `package.json`, `pnpm-workspace.yaml`
và các workspace package hợp lệ.

### Bước 3: Cấu hình môi trường

Sao chép `.env.example` thành `.env` bằng lệnh phù hợp với hệ điều hành
của bạn, sau đó cập nhật các giá trị local.

Windows PowerShell:

``` powershell
Copy-Item .env.example .env
```

macOS/Linux:

``` bash
cp .env.example .env
```

### Bước 4: Khởi động hạ tầng

``` bash
docker compose -f infrastructure/docker/docker-compose.yml up -d
```

Lệnh trên cần file Compose tồn tại và cấu hình PostgreSQL, Redis,
RabbitMQ. PostgreSQL cần khởi tạo database `sushi_platform`, các schema
và role có quyền giới hạn cho từng service. Kiểm tra trạng thái:

``` bash
docker compose -f infrastructure/docker/docker-compose.yml ps
```

RabbitMQ management UI có thể được publish ở
`http://localhost:15672` trong local. Không mở cổng management ra
Internet trong production.

### Bước 5: Database

Khi Prisma schema và migration riêng theo schema của service đã được tạo:

``` bash
pnpm --filter identity-service prisma:generate
pnpm --filter identity-service prisma:migrate:dev
```

Lặp lại với từng service. Đây là tên script minh họa; chỉ chạy khi đã
khai báo trong package tương ứng. Mỗi service chỉ generate client và
chạy migration cho schema mà service sở hữu trong database chung.

### Bước 6: Chạy ứng dụng

Các lệnh `pnpm dev`, `pnpm --filter <workspace-name> dev` hoặc lệnh
tương tự phải được khai báo trong `package.json` của workspace tương
ứng. README này không giả định các script đó đã tồn tại.

## 12. Quy ước phát triển

-   Dùng TypeScript và quy tắc format/lint thống nhất.
-   Đặt tên branch rõ ràng, ví dụ `feature/order-create`,
    `fix/stock-idempotency`.
-   Dùng migration để thay đổi database; không sửa schema production thủ
    công.
-   Mỗi thay đổi nghiệp vụ quan trọng cần cập nhật test và tài liệu.
-   Giữ API và event contract có version khi cần thay đổi không tương thích.
-   Không để frontend truy cập trực tiếp database.
-   Không ghi secret, token, thông tin thanh toán nhạy cảm hoặc dữ liệu
    cá nhân không cần thiết vào log.
-   Các thao tác tồn kho cần transaction, idempotency key và audit trail
    phù hợp.
-   Dùng UTC để lưu timestamp; chuyển đổi sang múi giờ địa phương ở giao
    diện khi hiển thị.
-   Mỗi service cần health check, log/metric riêng, quyền truy cập database
    tối thiểu và quy trình triển khai/rollback độc lập.

## 13. Kiểm thử và chất lượng

Tối thiểu cần có các lớp kiểm thử sau khi triển khai:

-   **Unit test:** quy tắc giá, công thức nguyên liệu, quy đổi đơn vị và
    chuyển trạng thái.
-   **Integration test:** transaction database trong từng service, outbox,
    RabbitMQ consumer, nhập kho, stock movement và idempotency.
-   **API test:** xác thực, phân quyền, validation và phản hồi lỗi.
-   **End-to-end test:** luồng đặt đơn từ storefront đến xử lý đơn và
    tiêu hao kho.
-   **Failure test:** message được giao lại, consumer restart, database lỗi
    tạm thời, retry và dead-letter queue.

Các tình huống quan trọng cần kiểm thử:

-   Một event được gửi lại nhưng chỉ tạo một tác động tồn kho.
-   Hai đơn đồng thời không làm số dư tồn bị ghi đè sai.
-   Ghi số dư và sổ biến động kho phải thành công hoặc thất bại cùng
    nhau.
-   Hủy đơn trước và sau khi bắt đầu chế biến được xử lý đúng chính
    sách.
-   Combo không làm trừ nguyên liệu hai lần.
-   Người dùng không thể đọc/ghi dữ liệu của chi nhánh hoặc kho ngoài
    phạm vi quyền.

## 14. Bảo mật

-   Xác thực và phân quyền ở backend.
-   Kiểm tra quyền theo vai trò và phạm vi chi nhánh/kho.
-   Validate mọi input và giới hạn kích thước request.
-   Dùng HTTPS ở môi trường triển khai công khai.
-   Bảo vệ endpoint webhook và xác thực chữ ký nếu tích hợp nhà cung cấp
    thanh toán.
-   Giới hạn truy cập mạng vào PostgreSQL, Redis và RabbitMQ.
-   Dùng secret manager hoặc cơ chế quản lý secret phù hợp ở production.
-   Sao lưu database và kiểm tra khả năng phục hồi định kỳ.
-   Thiết lập logging, metrics, health checks và cảnh báo cho từng service,
    database và queue.
-   Không dùng tài khoản database có quyền quản trị cho ứng dụng chạy
    thường ngày.

## 15. Lộ trình dự kiến

### Giai đoạn 1 --- Nền tảng

-   Khởi tạo monorepo, workspace và cấu hình code quality.
-   Docker Compose cho PostgreSQL, Redis và RabbitMQ.
-   Chốt ERD, migration và quy tắc phân quyền.
-   Xây dựng API Gateway, Identity Service và pipeline CI/CD cho service.

### Giai đoạn 2 --- Catalog và đặt hàng

-   Danh mục, sản phẩm, combo và công thức.
-   Storefront, giỏ hàng và tạo đơn Take Away.
-   Quản lý trạng thái đơn và lịch sử trạng thái.

### Giai đoạn 3 --- Kho và mua hàng

-   Nguyên liệu, đơn vị và quy đổi.
-   Nhà cung cấp, phiếu nhập và giá vốn.
-   Tồn kho, stock ledger, kiểm kê và điều chỉnh.
-   Tích hợp luồng đơn hàng với tiêu hao kho bằng RabbitMQ saga, outbox
    và idempotency; bảo đảm retry/compensation an toàn.

### Giai đoạn 4 --- Vận hành

-   Dashboard và báo cáo cơ bản.
-   Audit log, monitoring, backup/restore.
-   Tối ưu quyền truy cập và quy trình vận hành nhiều chi nhánh.

### Giai đoạn 5 --- Mở rộng

-   Thanh toán trực tuyến và webhook.
-   POS, mã vạch và ứng dụng di động.
-   Thông báo và báo cáo nâng cao khi có nhu cầu thực tế.

------------------------------------------------------------------------

## Ghi chú kiến trúc

README này là tài liệu định hướng. Trước khi xem một tính năng là sẵn
sàng sử dụng, hãy kiểm tra code, migration, environment variables,
Docker Compose, scripts, tests và tài liệu triển khai tương ứng. Hoàn
thiện luồng đầu-cuối qua các service, xác định rõ ownership dữ liệu,
contract, retry, idempotency và quan sát vận hành.
