//
//  MySQLSessions.swift
//  Perfect-Session-MySQLQL
//
//  Created by Jonathan Guthrie on 2016-12-19.
//
//

import TurnstileCrypto
import MySQL
import PerfectSession

public struct MySQLSessionConnector {

	public static var host: String		= "localhost"
	public static var username: String	= ""
	public static var password: String	= ""
	public static var database: String	= "perfect_sessions"
	public static var table: String		= "sessions"
	public static var port: Int			= 5432

	private init(){}

}


public struct MySQLSessions {

	/// Initializes the Session Manager. No config needed!
	public init() {}


	public func save(session: PerfectSession) {
		var s = session
		s.touch()
		// perform UPDATE
		let stmt = "UPDATE \(MySQLSessionConnector.table) SET userid = $1, updated = $2, idle = $3, data = $4 WHERE token = $5"
		exec(stmt, params: [
			session.userid,
			session.updated,
			session.idle,
			session.tojson(),
			session.token
			])
	}

	public func start() -> PerfectSession {
		let rand = URandom()
		var session = PerfectSession()
		session.token = rand.secureToken

		// perform INSERT
		let stmt = "INSERT INTO \(MySQLSessionConnector.table) (token,userid,created, updated, idle, data) VALUES($1,$2,$3,$4,$5,$6)"
		exec(stmt, params: [
			session.token,
			session.userid,
			session.created,
			session.updated,
			session.idle,
			session.tojson()
			])
		return session
	}

	/// Deletes the session for a session identifier.
	public func destroy(token: String) {
		let stmt = "DELETE FROM \(MySQLSessionConnector.table) WHERE token = $1"
		exec(stmt, params: [token])
	}

	public func resume(token: String) -> PerfectSession {
		var session = PerfectSession()
		let server = connect()
		let params = [token]
		var lastStatement = MySQLStmt(server)
		defer { lastStatement.close() }
		var _ = lastStatement.prepare(statement: "SELECT token,userid,created, updated, idle, data FROM \(MySQLSessionConnector.table) WHERE token = $1")

		for p in params {
			lastStatement.bindParam("\(p)")
		}

		_ = lastStatement.execute()

		let result = lastStatement.results()

		_ = result.forEachRow { row in

			session.token = row[0] as! String
			session.userid = row[1] as! String
			session.created = row[2] as! Int
			session.updated = row[3] as! Int
			session.idle = row[4] as! Int
			if let str = row[5] {
				session.fromjson(str as! String)
			}
		}

		server.close()
		return session
	}


	// MySQL Specific:
	func connect() -> MySQL {
		let server = MySQL()
		let _ = server.connect(
			host: MySQLSessionConnector.host,
			user: MySQLSessionConnector.username,
			password: MySQLSessionConnector.password,
			db: MySQLSessionConnector.database,
			port: UInt32(MySQLSessionConnector.port)
		)
		return server
	}

	func setup(){
		let stmt = "CREATE TABLE \"\(MySQLSessionConnector.table)\" (\"token\" varchar(255) NOT NULL, \"userid\" varchar(255), \"created\" int NOT NULL DEFAULT 0, \"updated\" int NOT NULL DEFAULT 0, \"idle\" int NOT NULL DEFAULT 0, \"data\" text, PRIMARY KEY \"token\";"
		exec(stmt, params: [])
	}

	func exec(_ statement: String, params: [Any]) {
		let server = connect()
		var lastStatement = MySQLStmt(server)
		defer { lastStatement.close() }
		var _ = lastStatement.prepare(statement: statement)

		for p in params {
			lastStatement.bindParam("\(p)")
		}

		_ = lastStatement.execute()

		let _ = lastStatement.results()
		server.close()
	}

	func isError(_ errorMsg: String) -> Bool {
		if errorMsg.contains(string: "ERROR") {
			print(errorMsg)
			return true
		}
		return false
	}

}



