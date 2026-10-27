# Authentication API Documentation

Base URL: `/api/v1/auth`

---

## 1. Register User

Creates a new user account with normalized fields and a secure password hash.

* **Method:** `POST`
* **Path:** `/api/v1/auth/register`
* **Path Parameters:** None
* **Query Parameters:** None
* **Request Headers:**
* `Content-Type: application/json`


* **Request Body (JSON):**
| Field | Type | Description |
| --- | --- | --- |
| `username` | String | The display username typed by the user. |
| `email` | String | The email address typed by the user. |
| `password` | String | The plaintext password (hashed with argon2id server-side). |


* **Responses:**
* **201 Created:** Account successfully created.
* **400 Bad Request:** Missing fields or validation errors.
* **409 Conflict:** Username or email already taken (unique constraint violation).
* **500 Internal Server Error:** Database or server error.



---

## 2. Login User

Authenticates a user via their identifier and password, returning access credentials.

* **Method:** `POST`
* **Path:** `/api/v1/auth/login`
* **Path Parameters:** None
* **Query Parameters:** None
* **Request Headers:**
* `Content-Type: application/json`


* **Request Body (JSON):**
| Field | Type | Description |
| --- | --- | --- |
| `identifier` | String | The username or email address. |
| `password` | String | The plaintext password. |


* **Responses:**
* **200 OK:** Successfully authenticated. Returns access/refresh tokens.
* **400 Bad Request:** Missing fields.
* **401 Unauthorized:** Invalid credentials.
* **500 Internal Server Error:** Database or server error.



---

## 3. Refresh Token

Exchanges a valid refresh token for a new access token.

* **Method:** `POST`
* **Path:** `/api/v1/auth/refresh`
* **Path Parameters:** None
* **Query Parameters:** None
* **Request Headers:**
* `Content-Type: application/json`


* **Request Body (JSON):**
| Field | Type | Description |
| --- | --- | --- |
| `refresh_token` | String | The active refresh token (alternatively handled via secure cookies). |


* **Responses:**
* **200 OK:** Returns a new access token.
* **401 Unauthorized:** Invalid or expired refresh token.
* **500 Internal Server Error:** Server error.



---

## 4. Logout User

Revokes the current session or refresh token.

* **Method:** `POST`
* **Path:** `/api/v1/auth/logout`
* **Path Parameters:** None
* **Query Parameters:** None
* **Request Headers:**
* `Authorization: Bearer <access_token>` (Protected)


* **Request Body (JSON):**
| Field | Type | Description |
| --- | --- | --- |
| `refresh_token` | String | Optional or required depending on token store implementation. |


* **Responses:**
* **200 OK:** Successfully logged out.
* **401 Unauthorized:** Missing or invalid access token.



---

## 5. Get Current User Profile

Retrieves account information for the currently authenticated user.

* **Method:** `GET`
* **Path:** `/api/v1/auth/me`
* **Path Parameters:** None
* **Query Parameters:** None
* **Request Headers:**
* `Authorization: Bearer <access_token>`


* **Request Body:** None
* **Responses:**
* **200 OK:** Returns the user profile payload (e.g., `user_id`, `username`, `email`, `created_at`).
* **401 Unauthorized:** Missing or invalid access token.
* **404 Not Found:** User record no longer exists.