//
//  MySQLSessionDriver.swift
//  Perfect-Session-MySQL
//
//  Created by Jonathan Guthrie on 2016-12-19.
//
//

import PerfectHTTP
import PerfectSession
import PerfectLogger
import Dispatch
import PerfectLib
import Foundation

public struct SessionMySQLDriver {
	public var requestFilter: (HTTPRequestFilter, HTTPFilterPriority)
	public var responseFilter: (HTTPResponseFilter, HTTPFilterPriority)
	let queue:DispatchQueue

	public init() {
		let filter = SessionMySQLFilter()
		requestFilter = (filter, HTTPFilterPriority.high)
		responseFilter = (filter, HTTPFilterPriority.high)

		queue = DispatchQueue(label: UUID().string)
		queue.asyncAfter(deadline: (.now() + Double(SessionConfig.purgeInterval))) {
			let s = MySQLSessions()
			s.clean()
		}
	}
}
public class SessionMySQLFilter {
	var driver = MySQLSessions()
	public init() {
		driver.setup()
	}
}

extension SessionMySQLFilter: HTTPRequestFilter {

	public func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
		if request.path != SessionConfig.healthCheckRoute {
			var createSession = true
			var session = PerfectSession()

			if let token = request.getCookie(name: SessionConfig.name) {
				// From Cookie
				session = driver.resume(token: token)
			} else if var bearer = request.header(.authorization), !bearer.isEmpty, bearer.hasPrefix("Bearer ") {
				// From Bearer Token
				bearer.removeFirst("Bearer ".count)
				session = driver.resume(token: bearer)

				// For OAuth2 Filters, add alternative load here.

			} else if let s = request.param(name: "session"), !s.isEmpty {
				// From Session Link
				session = driver.resume(token: s)
			}

			if !session.token.isEmpty {
				//				var session = driver.resume(token: token)
				if session.isValid(request) {
					session._state = "resume"
					request.session = session
					createSession = false
				} else {
					driver.destroy(request, response)
				}
			}
			if createSession, !session._isOAuth2 {
				//start new session
				request.session = driver.start(request)

			}

			if !session._isOAuth2 {
				// Now process CSRF
				if request.session?._state != "new" || request.method == .post {
					//print("Check CSRF Request: \(CSRFFilter.filter(request))")
					if !CSRFFilter.filter(request) {

						switch SessionConfig.CSRF.failAction {
						case .fail:
							response.status = .notAcceptable
							callback(.halt(request, response))
							return
						case .log:
							LogFile.info("CSRF FAIL")

						default:
							print("CSRF FAIL (console notification only)")
						}
					}
				}

				CORSheaders.make(request, response)
			}
		}
		callback(HTTPRequestFilterResult.continue(request, response))
	}

	public static func filterAPIRequest(data: [String:Any]) throws -> HTTPRequestFilter {
		return SessionMySQLFilter()
	}
}

extension SessionMySQLFilter: HTTPResponseFilter {

	/// Called once before headers are sent to the client.
	public func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {

		guard let session = response.request.session else {
			return callback(.continue)
		}

		// Zero point in saving an OAuth2 Session because it's not part of the normal session structure! 
		if !session._isOAuth2 {

			driver.save(session: session)
			let sessionID = session.token

			// 0.0.6 updates
			var domain = ""
			if !SessionConfig.cookieDomain.isEmpty {
				domain = SessionConfig.cookieDomain
			}

			if !sessionID.isEmpty {
				response.addCookie(HTTPCookie(
					name: SessionConfig.name,
					value: "\(sessionID)",
					domain: domain,
					expires: .relativeSeconds(SessionConfig.idle),
					path: SessionConfig.cookiePath,
					secure: SessionConfig.cookieSecure,
					httpOnly: SessionConfig.cookieHTTPOnly,
					sameSite: SessionConfig.cookieSameSite
					)
				)
				// CSRF Set Cookie
				if SessionConfig.CSRF.checkState {
					//print("in SessionConfig.CSRFCheckState")
					CSRFFilter.setCookie(response)
				}
			}
		}
		callback(.continue)
	}

	/// Called zero or more times for each bit of body data which is sent to the client.
	public func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
		callback(.continue)
	}

	public static func filterAPIResponse(data: [String:Any]) throws -> HTTPResponseFilter {
		return SessionMySQLFilter()
	}
}
