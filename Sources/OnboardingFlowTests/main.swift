import Foundation
import MiniTest
import ThinkingCapsCore

let t = MiniTest()

func test_noPermission_showsPermissionScreen() {
    t.check(OnboardingFlow.initialScreen(permissionGranted: false, hasCompletedOnboarding: false) == .permission,
            "no permission, never onboarded -> permission screen")
}

func test_noPermission_afterOnboarding_stillShowsPermissionScreen() {
    t.check(OnboardingFlow.initialScreen(permissionGranted: false, hasCompletedOnboarding: true) == .permission,
            "permission revoked after onboarding -> permission screen again")
}

func test_granted_firstTime_showsSuccessScreen() {
    t.check(OnboardingFlow.initialScreen(permissionGranted: true, hasCompletedOnboarding: false) == .success,
            "granted but onboarding not completed -> success screen")
}

func test_granted_alreadyOnboarded_showsNothing() {
    t.check(OnboardingFlow.initialScreen(permissionGranted: true, hasCompletedOnboarding: true) == nil,
            "granted and already onboarded -> no window")
}

test_noPermission_showsPermissionScreen()
test_noPermission_afterOnboarding_stillShowsPermissionScreen()
test_granted_firstTime_showsSuccessScreen()
test_granted_alreadyOnboarded_showsNothing()

t.finish()
