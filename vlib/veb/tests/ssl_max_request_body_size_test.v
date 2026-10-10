// vtest build: !sanitized_job? && !use_openssl?
import io
import net.mbedtls
import os
import time
import veb

const https_port = 13357
const limit = 1000
const exit_after = 20 * time.second

pub struct Context {
	veb.Context
}

pub struct App {
mut:
	started chan bool
}

// before_accept_loop tells the test that the server is listening.
pub fn (mut app App) before_accept_loop() {
	app.started <- true
}

// upload answers with the size of the request body.
@['/upload'; put]
pub fn (app &App) upload(mut ctx Context) veb.Result {
	return ctx.text('got ${ctx.req.data.len} bytes')
}

fn testsuite_begin() {
	spawn fn () {
		time.sleep(exit_after)
		assert true == false, 'timeout reached!'
		exit(1)
	}()
	mut app := &App{}
	spawn veb.run_at[App, Context](mut app,
		host:                  '127.0.0.1'
		port:                  https_port
		family:                .ip
		timeout_in_seconds:    2
		max_request_body_size: limit
		ssl_config:            mbedtls.SSLConnectConfig{
			cert:     os.join_path(@VMODROOT, 'examples', 'ssl_server', 'cert', 'server.crt')
			cert_key: os.join_path(@VMODROOT, 'examples', 'ssl_server', 'cert', 'server.key')
		}
	)
	_ := <-app.started
}

// put sends a request that has the given framing header and body in one TLS record,
// which the server reads completely, and returns the raw response.
fn put(framing string, body string) !string {
	mut conn := mbedtls.new_ssl_conn(validate: false)!
	conn.dial('127.0.0.1', https_port)!
	defer {
		conn.shutdown() or {}
	}
	conn.write_string('PUT /upload HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n${framing}\r\n\r\n${body}')!
	return io.read_all(reader: conn)!.bytestr()
}

fn test_https_body_with_content_length() {
	accepted := put('Content-Length: ${limit}', 'x'.repeat(limit))!
	assert accepted.starts_with('HTTP/1.1 200 OK'), accepted
	assert accepted.ends_with('got ${limit} bytes'), accepted
	rejected := put('Content-Length: ${limit + 1}', 'x'.repeat(limit + 1))!
	assert rejected.starts_with('HTTP/1.1 413 '), rejected
	assert rejected.contains('Connection: close'), rejected
}

fn test_https_chunked_body() {
	chunk := '${limit / 2:x}\r\n${'x'.repeat(limit / 2)}\r\n'
	accepted := put('Transfer-Encoding: chunked', chunk + chunk + '0\r\n\r\n')!
	assert accepted.starts_with('HTTP/1.1 200 OK'), accepted
	assert accepted.ends_with('got ${limit} bytes'), accepted
	rejected := put('Transfer-Encoding: chunked', chunk + chunk + '1\r\nx\r\n0\r\n\r\n')!
	assert rejected.starts_with('HTTP/1.1 413 '), rejected
	// the next client is still answered
	served := put('Content-Length: 2', 'ok')!
	assert served.starts_with('HTTP/1.1 200 OK'), served
	assert served.ends_with('got 2 bytes'), served
}
