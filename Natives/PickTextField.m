- (BOOL)prefersPopoverPresentation {
    BOOL hasLiquidGlass = NO;

    if (@available(iOS 26.0, *)) {
        hasLiquidGlass = YES;
    }

    return hasLiquidGlass || NSProcessInfo.processInfo.isMacCatalystApp;
}
