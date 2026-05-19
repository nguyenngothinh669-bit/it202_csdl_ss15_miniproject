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