public enum OnboardingScreen: Equatable {
    case permission
    case success
}

public enum OnboardingFlow {
    public static func initialScreen(permissionGranted: Bool, hasCompletedOnboarding: Bool) -> OnboardingScreen? {
        if !permissionGranted { return .permission }
        if !hasCompletedOnboarding { return .success }
        return nil
    }
}
