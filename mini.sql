-- KHỞI TẠO CƠ SỞ DỮ LIỆU NỀN TẢNG
CREATE DATABASE IF NOT EXISTS mini_social_network ; 
USE mini_social_network;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS post_logs; DROP TABLE IF EXISTS likes; DROP TABLE IF EXISTS friends;
DROP TABLE IF EXISTS comments; DROP TABLE IF EXISTS posts; DROP TABLE IF EXISTS users;
SET FOREIGN_KEY_CHECKS = 1;

-- Cấu trúc các bảng cơ sở theo SRS
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE posts (
    post_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE comments (
    comment_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE, -- Chiến lược xóa F10
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE friends (
    friendship_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_not_self CHECK (user_id != friend_id),
    CONSTRAINT chk_status CHECK (status IN ('pending', 'accepted')),
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (friend_id) REFERENCES users(user_id),
    -- MySQL 8+ Functional Index: Chặn trùng lặp đảo chiều (A-B và B-A)
    UNIQUE KEY idx_unique_friendship ((LEAST(user_id, friend_id)), (GREATEST(user_id, friend_id)))
);

CREATE TABLE likes (
    like_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    post_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE, -- Chiến lược xóa F10
    CONSTRAINT uq_user_post_like UNIQUE (user_id, post_id) -- Chặn trùng lặp F03
);

CREATE TABLE post_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT, author_id INT, deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
); 

-- F01: Đăng ký thành viên 

DELIMITER $$
CREATE PROCEDURE sp_add_user (
    IN  p_username VARCHAR(50),
    IN  p_password VARCHAR(255),
    IN  p_email    VARCHAR(100),
    OUT r_user_id  INT
)
BEGIN
    INSERT INTO users (username, password, email) 
    VALUES (p_username, p_password, p_email);
    
    SET r_user_id = LAST_INSERT_ID();
END$$
DELIMITER ; 

-- F02 : Đăng bài viết 
DELIMITER $$
CREATE PROCEDURE sp_create_post (
    IN  p_user_id INT,
    IN  p_content TEXT,
    OUT r_post_id INT
)
BEGIN
    INSERT INTO posts (user_id, content) 
    VALUES (p_user_id, p_content);
    
    SET r_post_id = LAST_INSERT_ID();
END$$
DELIMITER ; 

-- F03: Thích / Hủy thích bài viết 

DELIMITER $$

-- 1. Trigger tăng số lượt thích
CREATE TRIGGER trg_like_insert AFTER INSERT ON likes FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count + 1 WHERE post_id = NEW.post_id;
END$$

-- 2. Trigger giảm số lượt thích
CREATE TRIGGER trg_like_delete AFTER DELETE ON likes FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = IF(like_count > 0, like_count - 1, 0) WHERE post_id = OLD.post_id;
END$$

-- 3. Stored Procedure xử lý hành vi ấn nút Like (Toggle)
CREATE PROCEDURE sp_toggle_post_like (
    IN p_user_id INT,
    IN p_post_id INT
)
BEGIN
    IF EXISTS (SELECT 1 FROM likes WHERE user_id = p_user_id AND post_id = p_post_id) THEN
        DELETE FROM likes WHERE user_id = p_user_id AND post_id = p_post_id;
    ELSE
        INSERT INTO likes (user_id, post_id) VALUES (p_user_id, p_post_id);
    END IF;
END$$
DELIMITER ; 

-- F04: Gửi lời mời kết bạn 
DELIMITER $$
CREATE PROCEDURE sp_send_friend_request (
    IN p_user_id   INT,
    IN p_friend_id INT
)
BEGIN
    
    INSERT INTO friends (user_id, friend_id, status) 
    VALUES (p_user_id, p_friend_id, 'pending');
END$$
DELIMITER ;  

-- F05: Chấp nhận / Hủy kết bạn 

DELIMITER $$
CREATE PROCEDURE sp_respond_friend_request (
    IN p_friendship_id INT,
    IN p_action VARCHAR(20)
)
BEGIN
    IF p_action = 'accept' THEN
        UPDATE friends 
        SET status = 'accepted' 
        WHERE friendship_id = p_friendship_id;
    ELSEIF p_action = 'reject' THEN
        DELETE FROM friends
        WHERE friendship_id = p_friendship_id;
    END IF;
END$$
DELIMITER ; 

-- F06: Xem thông tin người dùng 
CREATE VIEW vw_user_profiles AS
SELECT 
    user_id,
    username,
    email,
    created_at AS join_date
FROM users;   

-- F07: Xem bài viết theo từ khóa 

-- Khởi tạo chỉ mục Full-text Search
ALTER TABLE posts ADD FULLTEXT idx_posts_content_fts (content);

DELIMITER $$
CREATE PROCEDURE sp_search_posts (
    IN p_keyword VARCHAR(100)
)
BEGIN
    SELECT post_id, user_id, content, like_count, comment_count, created_at
    FROM posts
    WHERE MATCH(content) AGAINST(p_keyword IN NATURAL LANGUAGE MODE);
END$$
DELIMITER ; 




