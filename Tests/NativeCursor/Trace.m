// Simulator-only instrumentation. Never link this into the shipped keyboard.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

static id call0(id obj, const char *sel) { return ((id(*)(id,SEL))objc_msgSend)(obj,sel_registerName(sel)); }
static id shared(const char *cls) { return call0((id)objc_getClass(cls),"sharedInstance"); }
static void logLine(NSString *line) { printf("PROBE t=%.6f %s\n",CACurrentMediaTime(),line.UTF8String); fflush(stdout); }
static void(*originalPan)(id,SEL,id);
static void pan(id obj,SEL sel,UIGestureRecognizer *g) {
    CGPoint p=CGPointZero,v=CGPointZero;
    if ([g respondsToSelector:@selector(translationInView:)]) p=((CGPoint(*)(id,SEL,id))objc_msgSend)(g,@selector(translationInView:),g.view);
    if ([g respondsToSelector:@selector(velocityInView:)]) v=((CGPoint(*)(id,SEL,id))objc_msgSend)(g,@selector(velocityInView:),g.view);
    logLine([NSString stringWithFormat:@"PAN before class=%@ state=%ld translation=%@ velocity=%@",NSStringFromClass(g.class),(long)g.state,NSStringFromCGPoint(p),NSStringFromCGPoint(v)]);
    originalPan(obj,sel,g);
    id owner=call0(obj,"owner");
    logLine([NSString stringWithFormat:@"PAN after %@",[owner dictionaryWithValuesForKeys:@[@"isSpacePan",@"isPanning",@"isLongPressing",@"hadAddedTouch",@"spacePanDistance",@"lastPanTranslation",@"accumulatedAcceleration",@"accumulatedBounding",@"cursorLocationBase"]]]);
}
static void(*originalTrackpad)(id,SEL,BOOL,BOOL);
static void trackpad(id obj,SEL sel,BOOL active,BOOL animated) {
    logLine([NSString stringWithFormat:@"TRACKPAD active=%d animated=%d",active,animated]); originalTrackpad(obj,sel,active,animated);
}
static void(*originalEvent)(id,SEL,UIEvent *);
static void event(id obj,SEL sel,UIEvent *e) {
    for(UITouch *t in e.allTouches) if(t.phase!=UITouchPhaseStationary) logLine([NSString stringWithFormat:@"TOUCH timestamp=%.6f phase=%ld point=%@ view=%@",t.timestamp,(long)t.phase,NSStringFromCGPoint([t locationInView:t.window]),NSStringFromClass(t.view.class)]);
    originalEvent(obj,sel,e);
}
static void(*originalBegin)(id,SEL,CGPoint);
static void begin(id obj,SEL sel,CGPoint p) {logLine([NSString stringWithFormat:@"FLOAT begin %@",NSStringFromCGPoint(p)]);originalBegin(obj,sel,p);}
static void(*originalUpdate)(id,SEL,CGPoint);
static void update(id obj,SEL sel,CGPoint p) {logLine([NSString stringWithFormat:@"FLOAT update %@",NSStringFromCGPoint(p)]);originalUpdate(obj,sel,p);}
static void(*originalEnd)(id,SEL);
static void end(id obj,SEL sel) {logLine(@"FLOAT end");originalEnd(obj,sel);}
static double(*originalCadence)(id,SEL,id);
static double cadence(id obj,SEL sel,id gesture) {double v=originalCadence(obj,sel,gesture);logLine([NSString stringWithFormat:@"CADENCE extra=%.6f gesture=%@",v,gesture]);return v;}
static void hook(const char *cls,const char *sel,IMP imp,IMP *original) {
    Method m=class_getInstanceMethod(objc_getClass(cls),sel_registerName(sel));
    if(m){*original=method_getImplementation(m); method_setImplementation(m,imp);}
    else logLine([NSString stringWithFormat:@"MISSING %s %s",cls,sel]);
}
static void dumpView(UIView *view) {
    for(UIGestureRecognizer *g in view.gestureRecognizers) {
        NSMutableString *s=[NSMutableString stringWithFormat:@"GESTURE view=%@ class=%@ state=%ld delegate=%@",NSStringFromClass(view.class),NSStringFromClass(g.class),(long)g.state,g.delegate];
        if([g respondsToSelector:@selector(minimumPressDuration)]) [s appendFormat:@" duration=%@ movement=%@",[g valueForKey:@"minimumPressDuration"],[g valueForKey:@"allowableMovement"]];
        logLine(s);
    }
    for(UIView *v in view.subviews)dumpView(v);
}
void ProbeDumpState(void) {
    id settings=shared("_UITextSelectionSettings");
    logLine([NSString stringWithFormat:@"SETTINGS %@",[settings dictionaryWithValuesForKeys:@[@"gain",@"linear",@"parabolic",@"shouldUseAcceleration",@"allowExtendingSelections",@"shouldPreferEndOfWord",@"allowableSeparation",@"allowableForceMovement"]]]);
    id curve=call0((id)objc_getClass("_UICubicPolyTangent"),"keyboardTrackpadCurve");
    logLine([NSString stringWithFormat:@"CURVE %@",[curve dictionaryWithValuesForKeys:@[@"initialLinearGain",@"parabolicGain",@"cubicGain",@"quarticGain",@"tangentLineSpeed",@"tangentSqrtSpeed"]]]);
    UIView *keyboard=call0((id)objc_getClass("UIKeyboard"),"activeKeyboard");
    if(keyboard)dumpView(keyboard);
}
void ProbeSampleCurve(void) {
    id curve=call0((id)objc_getClass("_UICubicPolyTangent"),"keyboardTrackpadCurve");
    double values[]={0,0.25,0.5,1,1.5,2,2.5,3,4,5,6,8,10,16,32};
    for(unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++) {
        double gain=((double(*)(id,SEL,double))objc_msgSend)(curve,sel_registerName("piecewiseCubicAcceleratedSpeed:"),values[i]);
        logLine([NSString stringWithFormat:@"CURVE_SAMPLE step=%.9g extraGain=%.9g totalGain=%.9g",values[i],gain,1+gain]);
    }
}
void ProbeInstallTrace(void) {
    hook("_UIKeyboardTextSelectionInteraction","panningGesture:",(IMP)pan,(IMP *)&originalPan);
    hook("UIKeyboardLayoutStar","setTrackpadMode:animated:",(IMP)trackpad,(IMP *)&originalTrackpad);
    hook("UIApplication","sendEvent:",(IMP)event,(IMP *)&originalEvent);
    hook("UITextView","beginFloatingCursorAtPoint:",(IMP)begin,(IMP *)&originalBegin);
    hook("UITextView","updateFloatingCursorAtPoint:",(IMP)update,(IMP *)&originalUpdate);
    hook("UITextView","endFloatingCursor",(IMP)end,(IMP *)&originalEnd);
    hook("_UIKeyboardTextSelectionInteraction","additionalPressDurationForTypingCadence:",(IMP)cadence,(IMP *)&originalCadence);
    logLine(@"TRACE installed"); ProbeDumpState(); ProbeSampleCurve();
}
