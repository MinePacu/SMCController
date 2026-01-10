import Foundation
import Security

print("Testing Authorization API...")

var authRef: AuthorizationRef?
var status = AuthorizationCreate(nil, nil, [], &authRef)

print("AuthorizationCreate: \(status)")

if status == errAuthorizationSuccess, let auth = authRef {
    var authItem = AuthorizationItem(
        name: kAuthorizationRightExecute,
        valueLength: 0,
        value: nil,
        flags: 0
    )
    
    var authRights = AuthorizationRights(count: 1, items: &authItem)
    let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
    status = AuthorizationCopyRights(auth, &authRights, nil, flags, nil)
    
    print("AuthorizationCopyRights: \(status)")
    
    if status == errAuthorizationSuccess {
        print("✅ Authorization successful!")
    } else {
        print("❌ Authorization failed: \(status)")
    }
    
    AuthorizationFree(auth, [])
} else {
    print("❌ Failed to create auth")
}
