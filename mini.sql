CREATE DATABASE IF NOT EXISTS mini_social_network
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE mini_social_network;

--  RESET (dev/re-run)
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS post_logs;
DROP TABLE IF EXISTS likes;
DROP TABLE IF EXISTS friends;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS posts;
DROP TABLE IF EXISTS users;
DROP PROCEDURE IF EXISTS sp_register_user;
DROP PROCEDURE IF EXISTS sp_add_post;
DROP PROCEDURE IF EXISTS sp_send_friend_request;
DROP PROCEDURE IF EXISTS sp_accept_friend_request;
DROP PROCEDURE IF EXISTS sp_cancel_friend_request;
DROP PROCEDURE IF EXISTS sp_delete_post;
DROP PROCEDURE IF EXISTS sp_delete_user_account;
DROP PROCEDURE IF EXISTS SuggestFriends;
DROP VIEW IF EXISTS vw_user_profile;
DROP VIEW IF EXISTS vw_user_activity_stats;
DROP TRIGGER IF EXISTS trg_increase_like_count;
DROP TRIGGER IF EXISTS trg_decrease_like_count;
DROP TRIGGER IF EXISTS trg_audit_post_delete;
SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
--  DDL — Cấu trúc bảng
-- ============================================================

CREATE TABLE users (
    user_id    INT          NOT NULL AUTO_INCREMENT,
    username   VARCHAR(50)  NOT NULL,
    password   VARCHAR(255) NOT NULL,           -- lưu SHA-256 hash
    email      VARCHAR(100) NOT NULL,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_username (username),
    UNIQUE KEY uq_email    (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE posts (
    post_id       INT  NOT NULL AUTO_INCREMENT,
    user_id       INT  NOT NULL,
    content       TEXT NOT NULL,
    like_count    INT  NOT NULL DEFAULT 0,
    comment_count INT  NOT NULL DEFAULT 0,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id),
    KEY idx_posts_user_id (user_id),
    -- FIX F07: FULLTEXT index bắt buộc để MATCH...AGAINST hoạt động
    FULLTEXT KEY ft_posts_content (content),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE comments (
    comment_id INT  NOT NULL AUTO_INCREMENT,
    post_id    INT  NOT NULL,
    user_id    INT  NOT NULL,
    content    TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (comment_id),
    KEY idx_comments_post_id  (post_id),
    KEY idx_comments_user_id  (user_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE friends (
    friendship_id INT         NOT NULL AUTO_INCREMENT,
    user_id       INT         NOT NULL,
    friend_id     INT         NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (friendship_id),
    -- Đảm bảo (A,B) và (B,A) là một cặp duy nhất
    UNIQUE KEY uq_friendship (
        (LEAST(user_id, friend_id)),
        (GREATEST(user_id, friend_id))
    ),
    CONSTRAINT chk_not_self  CHECK (user_id <> friend_id),
    CONSTRAINT chk_status    CHECK (status IN ('pending', 'accepted')),
    KEY idx_friends_user_id   (user_id),
    KEY idx_friends_friend_id (friend_id),
    FOREIGN KEY (user_id)   REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (friend_id) REFERENCES users(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE likes (
    like_id    INT  NOT NULL AUTO_INCREMENT,
    user_id    INT  NOT NULL,
    post_id    INT  NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (like_id),
    -- FIX F03: constraint chặn duplicate like
    UNIQUE KEY uq_user_post_like (user_id, post_id),
    KEY idx_likes_post_id (post_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE post_logs (
    log_id     INT      NOT NULL AUTO_INCREMENT,
    post_id    INT,                               -- nullable: giữ lịch sử dù post đã xóa
    author_id  INT,
    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
--  F01 — Đăng ký tài khoản
-- ============================================================
DELIMITER //

CREATE PROCEDURE sp_register_user(
    IN  p_username VARCHAR(50),
    IN  p_password VARCHAR(255),
    IN  p_email    VARCHAR(100),
    OUT p_result   VARCHAR(200)
)
BEGIN
    -- Kiểm tra trùng username / email
    IF EXISTS (
        SELECT 1 FROM users
        WHERE username = p_username OR email = p_email
    ) THEN
        SET p_result = 'ERROR: Username hoặc Email đã tồn tại.';
    ELSE
        INSERT INTO users (username, password, email)
        VALUES (p_username, SHA2(p_password, 256), p_email);

        SET p_result = CONCAT('OK: Đăng ký thành công, user_id = ', LAST_INSERT_ID());
    END IF;
END //

DELIMITER ;



--  F02 — Đăng bài viết

DELIMITER //

CREATE PROCEDURE sp_add_post(
    IN  p_user_id INT,
    IN  p_content TEXT,
    OUT p_result  VARCHAR(200)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        SET p_result = 'ERROR: Người dùng không tồn tại.';

    ELSEIF p_content IS NULL OR TRIM(p_content) = '' THEN
        SET p_result = 'ERROR: Nội dung bài viết không được để trống.';

    ELSE
        INSERT INTO posts (user_id, content) VALUES (p_user_id, p_content);
        SET p_result = CONCAT('OK: Đăng bài thành công, post_id = ', LAST_INSERT_ID());
    END IF;
END //

DELIMITER ;


-- ============================================================
--  F03 — Thích / Hủy thích bài viết (Triggers)
-- ============================================================
DELIMITER //

CREATE TRIGGER trg_increase_like_count
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET like_count = like_count + 1
    WHERE post_id = NEW.post_id;
END //


CREATE TRIGGER trg_decrease_like_count
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET like_count = like_count - 1
    WHERE post_id = OLD.post_id;
END //

DELIMITER ;


--  F04 — Gửi lời mời kết bạn

DELIMITER //

CREATE PROCEDURE sp_send_friend_request(
    IN  p_user_id   INT,
    IN  p_friend_id INT,
    OUT p_result    VARCHAR(200)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_result = 'ERROR: Không thể gửi lời mời (lỗi hệ thống).';
    END;

    IF p_user_id = p_friend_id THEN
        SET p_result = 'ERROR: Không thể tự kết bạn với chính mình.';

    ELSEIF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        SET p_result = 'ERROR: Người gửi không tồn tại.';

    ELSEIF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_friend_id) THEN
        SET p_result = 'ERROR: Người nhận không tồn tại.';

    ELSEIF EXISTS (
        SELECT 1 FROM friends
        WHERE LEAST(user_id, friend_id)    = LEAST(p_user_id, p_friend_id)
          AND GREATEST(user_id, friend_id) = GREATEST(p_user_id, p_friend_id)
    ) THEN
        SET p_result = 'ERROR: Lời mời kết bạn hoặc quan hệ bạn bè đã tồn tại.';

    ELSE
        INSERT INTO friends (user_id, friend_id, status)
        VALUES (p_user_id, p_friend_id, 'pending');

        SET p_result = CONCAT('OK: Đã gửi lời mời kết bạn, friendship_id = ', LAST_INSERT_ID());
    END IF;
END //

DELIMITER ;


--  F05a — Chấp nhận lời mời kết bạn

DELIMITER //

CREATE PROCEDURE sp_accept_friend_request(
    IN  p_friendship_id INT,
    IN  p_friend_id     INT,     -- người nhận lời mời (xác thực quyền)
    OUT p_result        VARCHAR(200)
)
BEGIN
    DECLARE v_status  VARCHAR(20) DEFAULT '';
    DECLARE v_recv_id INT         DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'ERROR: Không thể chấp nhận lời mời.';
    END;

    START TRANSACTION;

    SELECT status, friend_id
    INTO   v_status, v_recv_id
    FROM   friends
    WHERE  friendship_id = p_friendship_id
    FOR UPDATE;

    IF v_recv_id <> p_friend_id THEN
        ROLLBACK;
        SET p_result = 'ERROR: Bạn không có quyền chấp nhận lời mời này.';

    ELSEIF v_status <> 'pending' THEN
        ROLLBACK;
        SET p_result = 'ERROR: Lời mời không ở trạng thái pending.';

    ELSE
        UPDATE friends
        SET    status = 'accepted'
        WHERE  friendship_id = p_friendship_id;

        COMMIT;
        SET p_result = 'OK: Đã chấp nhận lời mời kết bạn.';
    END IF;
END //

DELIMITER ;

--  F05b — Hủy / Từ chối lời mời kết bạn

DELIMITER //

CREATE PROCEDURE sp_cancel_friend_request(
    IN  p_friendship_id INT,
    IN  p_user_id       INT,     -- phải là người gửi HOẶC người nhận
    OUT p_result        VARCHAR(200)
)
BEGIN
    DECLARE v_count INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_result = 'ERROR: Không thể hủy lời mời.';
    END;

    SELECT COUNT(*) INTO v_count
    FROM   friends
    WHERE  friendship_id = p_friendship_id
      AND  (user_id = p_user_id OR friend_id = p_user_id)
      AND  status = 'pending';     -- chỉ hủy được khi còn pending

    IF v_count = 0 THEN
        SET p_result = 'ERROR: Không tìm thấy lời mời hoặc đã được xử lý.';
    ELSE
        DELETE FROM friends WHERE friendship_id = p_friendship_id;
        SET p_result = 'OK: Đã hủy lời mời kết bạn.';
    END IF;
END //

DELIMITER ;


-- ============================================================
--  F06 — Xem thông tin người dùng (View)
-- ============================================================
CREATE OR REPLACE VIEW vw_user_profile AS
SELECT
    u.user_id,
    u.username,
    u.email,
    u.created_at,
    COUNT(DISTINCT p.post_id)       AS total_posts,
    COALESCE(SUM(p.like_count), 0)    AS total_likes_received,
    COALESCE(SUM(p.comment_count), 0) AS total_comments_received
FROM  users u
LEFT JOIN posts p ON u.user_id = p.user_id
GROUP BY u.user_id, u.username, u.email, u.created_at;


-- ============================================================
--  F07 — Tìm kiếm bài viết theo từ khóa (Full-Text Search)
--  FIX: FULLTEXT INDEX đã được khai báo trong DDL ở trên.
--       Sử dụng Stored Procedure để tái sử dụng dễ dàng.
-- ============================================================
DELIMITER //

CREATE PROCEDURE sp_search_posts(
    IN p_keyword VARCHAR(255)
)
BEGIN
    IF p_keyword IS NULL OR TRIM(p_keyword) = '' THEN
        SELECT 'ERROR: Từ khóa không được để trống.' AS message;
    ELSE
        SELECT
            p.post_id,
            p.user_id,
            u.username,
            p.content,
            p.like_count,
            p.comment_count,
            p.created_at,
            MATCH(p.content) AGAINST (p_keyword IN NATURAL LANGUAGE MODE) AS relevance_score
        FROM posts p
        JOIN users u ON p.user_id = u.user_id
        WHERE MATCH(p.content) AGAINST (p_keyword IN NATURAL LANGUAGE MODE)
        ORDER BY relevance_score DESC;
    END IF;
END //

DELIMITER ;



--  F08 — Báo cáo hoạt động người dùng (View)

CREATE OR REPLACE VIEW vw_user_activity_stats AS
SELECT
    u.user_id,
    u.username,
    COUNT(DISTINCT p.post_id)    AS total_posts,
    COUNT(DISTINCT l.like_id)    AS total_likes_given,
    COUNT(DISTINCT c.comment_id) AS total_comments_written
FROM  users u
LEFT JOIN posts    p ON u.user_id = p.user_id
LEFT JOIN likes    l ON u.user_id = l.user_id
LEFT JOIN comments c ON u.user_id = c.user_id
GROUP BY u.user_id, u.username;


--  F09 — Gợi ý kết bạn (Mutual Friends)

DELIMITER //

CREATE PROCEDURE SuggestFriends(
    IN p_user_id INT
)
BEGIN
    WITH accepted_friends AS (
        -- Lấy tất cả bạn bè đã accepted của p_user_id (cả 2 chiều)
        SELECT friend_id AS friend_user FROM friends
        WHERE  user_id = p_user_id AND status = 'accepted'
        UNION
        SELECT user_id  AS friend_user FROM friends
        WHERE  friend_id = p_user_id AND status = 'accepted'
    ),
    mutual_candidates AS (
        -- Tìm người chưa phải bạn của p_user_id
        -- nhưng có bạn chung (accepted) với p_user_id
        SELECT f.friend_id AS suggested_user, COUNT(*) AS mutual_count
        FROM   friends f
        INNER JOIN accepted_friends af ON f.user_id = af.friend_user
        WHERE  f.friend_id <> p_user_id
          AND  f.status = 'accepted'
        GROUP BY f.friend_id

        UNION ALL

        -- FIX: xét chiều ngược (bạn của bạn có thể là user_id trong bảng friends)
        SELECT f.user_id AS suggested_user, COUNT(*) AS mutual_count
        FROM   friends f
        INNER JOIN accepted_friends af ON f.friend_id = af.friend_user
        WHERE  f.user_id <> p_user_id
          AND  f.status = 'accepted'
        GROUP BY f.user_id
    ),
    aggregated AS (
        SELECT suggested_user, SUM(mutual_count) AS mutual_count
        FROM   mutual_candidates
        GROUP BY suggested_user
    )
    SELECT
        u.user_id,
        u.username,
        a.mutual_count
    FROM  aggregated a
    INNER JOIN users u ON a.suggested_user = u.user_id
    -- Loại trừ người đã là bạn hoặc đã có lời mời
    WHERE a.suggested_user NOT IN (SELECT friend_user FROM accepted_friends)
      AND NOT EXISTS (
            SELECT 1 FROM friends
            WHERE LEAST(user_id, friend_id)    = LEAST(p_user_id, a.suggested_user)
              AND GREATEST(user_id, friend_id) = GREATEST(p_user_id, a.suggested_user)
      )
    ORDER BY a.mutual_count DESC, u.username ASC;
END //

DELIMITER ;



--  F10 — Quản lý xóa bài viết

DELIMITER //

CREATE TRIGGER trg_audit_post_delete
AFTER DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id, author_id)
    VALUES (OLD.post_id, OLD.user_id);
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE sp_delete_post(
    IN  p_user_id INT,
    IN  p_post_id INT,
    OUT p_result  VARCHAR(200)
)
BEGIN
    DECLARE v_count INT DEFAULT 0;

    SELECT COUNT(*) INTO v_count
    FROM posts
    WHERE post_id = p_post_id AND user_id = p_user_id;

    IF v_count = 0 THEN
        SET p_result = 'ERROR: Bài viết không tồn tại hoặc bạn không có quyền xóa.';
    ELSE
        DELETE FROM posts WHERE post_id = p_post_id AND user_id = p_user_id;
        SET p_result = 'OK: Đã xóa bài viết thành công.';
    END IF;
END //

DELIMITER ;



--  F11 — Xóa tài khoản người dùng (Transaction)
DELIMITER //

CREATE PROCEDURE sp_delete_user_account(
    IN  p_user_id INT,
    OUT p_result  VARCHAR(200)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'ERROR: Không thể xóa tài khoản, đã rollback.';
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        SET p_result = 'ERROR: Tài khoản không tồn tại.';
    ELSE
        START TRANSACTION;

            -- 1. Xóa quan hệ bạn bè (cả 2 chiều)
            DELETE FROM friends
            WHERE user_id = p_user_id OR friend_id = p_user_id;

            -- 2. Xóa lượt thích do user này tạo ra
            DELETE FROM likes WHERE user_id = p_user_id;

            -- 3. Xóa bình luận do user này viết
            DELETE FROM comments WHERE user_id = p_user_id;

            -- 4. Xóa bài viết (CASCADE tự xóa likes/comments của người khác trên bài này)
            DELETE FROM posts WHERE user_id = p_user_id;

            -- 5. Xóa tài khoản gốc
            DELETE FROM users WHERE user_id = p_user_id;

        COMMIT;
        SET p_result = 'OK: Đã xóa tài khoản và toàn bộ dữ liệu liên quan.';
    END IF;
END //

DELIMITER ;


-- ============================================================
--  SEED DATA — Dữ liệu mẫu để kiểm thử
-- ============================================================
SET @r = '';

CALL sp_register_user('alice',   'pass_alice',   'alice@example.com',   @r); SELECT @r;
CALL sp_register_user('bob',     'pass_bob',     'bob@example.com',     @r); SELECT @r;
CALL sp_register_user('charlie', 'pass_charlie', 'charlie@example.com', @r); SELECT @r;
CALL sp_register_user('diana',   'pass_diana',   'diana@example.com',   @r); SELECT @r;

CALL sp_add_post(1, 'Alice chia sẻ mẹo học Python hiệu quả!', @r);     SELECT @r;
CALL sp_add_post(1, 'Alice: SQL Stored Procedure rất mạnh.', @r);       SELECT @r;
CALL sp_add_post(2, 'Bob đang học Machine Learning với Python.', @r);   SELECT @r;
CALL sp_add_post(3, 'Charlie review sách Clean Code.', @r);             SELECT @r;

-- Kiểm thử lỗi F02
CALL sp_add_post(999, 'User không tồn tại', @r);  SELECT @r;
CALL sp_add_post(1,   '',                   @r);  SELECT @r;

-- Likes (trigger F03)
INSERT INTO likes (user_id, post_id) VALUES (2, 1), (3, 1), (4, 1);
INSERT INTO likes (user_id, post_id) VALUES (1, 3), (4, 3);

-- Comments
INSERT INTO comments (post_id, user_id, content) VALUES (1, 2, 'Rất hữu ích, cảm ơn Alice!');
INSERT INTO comments (post_id, user_id, content) VALUES (1, 3, 'Mình cũng đang học Python.');
INSERT INTO comments (post_id, user_id, content) VALUES (3, 1, 'Sách này tuyệt vời!');

-- Kết bạn (F04, F05a, F05b)
CALL sp_send_friend_request(1, 2, @r); SELECT @r;   -- alice → bob
CALL sp_send_friend_request(1, 3, @r); SELECT @r;   -- alice → charlie
CALL sp_send_friend_request(2, 3, @r); SELECT @r;   -- bob   → charlie
CALL sp_send_friend_request(3, 4, @r); SELECT @r;   -- charlie → diana
CALL sp_send_friend_request(1, 1, @r); SELECT @r;   -- lỗi: tự kết bạn

CALL sp_accept_friend_request(1, 2, @r); SELECT @r; -- bob chấp nhận alice
CALL sp_accept_friend_request(2, 3, @r); SELECT @r; -- charlie chấp nhận alice
CALL sp_accept_friend_request(3, 3, @r); SELECT @r; -- charlie chấp nhận bob
CALL sp_accept_friend_request(4, 4, @r); SELECT @r; -- diana chấp nhận charlie

-- Kiểm tra gợi ý bạn bè (F09): diana nên được gợi ý với alice/bob qua charlie
CALL SuggestFriends(4);

-- Kiểm tra tìm kiếm full-text (F07)
CALL sp_search_posts('Python');

-- Xem views (F06, F08)
SELECT * FROM vw_user_profile;
SELECT * FROM vw_user_activity_stats;

-- Xóa bài (F10)
CALL sp_delete_post(1, 2, @r); SELECT @r;  -- alice xóa post_id=2
CALL sp_delete_post(2, 1, @r); SELECT @r;  -- bob cố xóa bài của alice → lỗi

SELECT * FROM post_logs;  -- kiểm tra audit log

-- Xóa tài khoản (F11)
CALL sp_delete_user_account(4, @r); SELECT @r;
SELECT COUNT(*) AS remaining_users FROM users;