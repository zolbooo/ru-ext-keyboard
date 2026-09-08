// Simulator-only direct method tests for the reconstructed native math.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static id send0(id obj,const char *name) {return ((id(*)(id,SEL))objc_msgSend)(obj,sel_registerName(name));}
static NSArray *pointJSON(CGPoint p) {return @[@(p.x),@(p.y)];}
static BOOL near(double a,double b) {return fabs(a-b)<=1e-10*fmax(1,fabs(b));}
static BOOL nearPoint(CGPoint a,CGPoint b) {return near(a.x,b.x)&&near(a.y,b.y);}
static double reconstructedGain(double s) {
    if(s<=2)return 0.04*s*s;
    if(s<=5)return 0.16*s-0.16;
    return sqrt(0.2048*s-0.6144);
}
@interface ProbeClipView : UIView
@end
@implementation ProbeClipView
- (CGRect)selectionClipRect {return self.bounds;}
- (UIView *)textInputView {return self;}
@end
@interface ProbeSelectionManager : NSObject
@property(nonatomic,strong) ProbeClipView *textInput;
@property(nonatomic,strong) UIView *cursor;
@end
@implementation ProbeSelectionManager
- (UIView *)_hostViewAboveText {return self.textInput;}
- (UIView *)_cursorView {return self.cursor;}
@end

@interface ProbeBoundaryController : NSObject
@property(nonatomic) CGPoint correction;
@end
@implementation ProbeBoundaryController
- (CGPoint)boundedDeltaForTranslation:(CGPoint)translation cursorLocationBase:(CGPoint)base {return self.correction;}
@end
@interface ProbeBoundaryDelegate : NSObject
@property(nonatomic,strong) ProbeBoundaryController *textSelectionController;
@end
@implementation ProbeBoundaryDelegate
@end
static double reconstructedBounding(double previous,double correction) {
    if(previous>0) {
        if(correction>previous)return correction;
        return correction<0?previous+correction:previous;
    }
    if(correction<previous)return correction;
    return correction>0?previous+correction:previous;
}

BOOL ProbeRunMath(id interaction,id recognizer) {
    NSMutableDictionary *result=[@{@"os":UIDevice.currentDevice.systemVersion,@"kind":@"direct-native-method-tests"} mutableCopy];
    NSMutableArray *failures=[NSMutableArray new];
    @try {
        result[@"recognizer"]=[recognizer dictionaryWithValuesForKeys:@[@"minimumPressDuration",@"allowableMovement",@"minimumNumberOfTouches",@"maximumNumberOfTouches",@"longPressOnly"]];
        NSArray *regions=send0([(UIGestureRecognizer *)recognizer view],"_keyboardLongPressInteractionRegions");
        NSMutableArray *regionJSON=[NSMutableArray new];
        for(NSValue *region in regions)[regionJSON addObject:NSStringFromCGRect(region.CGRectValue)];
        result[@"longPressRegions"]=regionJSON;
        id settings=send0((id)NSClassFromString(@"_UITextSelectionSettings"),"sharedInstance");
        result[@"settings"]=[settings dictionaryWithValuesForKeys:@[@"gain",@"linear",@"parabolic",@"shouldUseAcceleration",@"allowExtendingSelections",@"shouldPreferEndOfWord"]];
        id curve=send0((id)NSClassFromString(@"_UICubicPolyTangent"),"keyboardTrackpadCurve");
        NSMutableArray *samples=[NSMutableArray new]; double maximumError=0; NSUInteger count=0;
        for(int i=0;i<=320;i++) {
            double s=i/8.0;
            double native=((double(*)(id,SEL,double))objc_msgSend)(curve,sel_registerName("piecewiseCubicAcceleratedSpeed:"),s);
            double expected=reconstructedGain(s); maximumError=fmax(maximumError,fabs(native-expected));count++;
            if(!near(native,expected))[failures addObject:[NSString stringWithFormat:@"curve step=%g native=%g expected=%g",s,native,expected]];
            if(i%8==0&&i<=128)[samples addObject:@{@"step":@(s),@"nativeExtraGain":@(native),@"reconstructedExtraGain":@(expected)}];
        }
        result[@"curve"]=@{@"tested":@(count),@"maximumAbsoluteError":@(maximumError),@"samples":samples};
        // These two properties are restored even on a native exception. No gesture
        // is synthesized; call this only while the keyboard gesture is idle.
        id owner=send0(interaction,"owner");
        NSDictionary *saved=[owner dictionaryWithValuesForKeys:@[@"lastPanTranslation",@"accumulatedAcceleration"]];
        @try {
            [owner setValue:[NSValue valueWithCGPoint:CGPointZero] forKey:@"lastPanTranslation"];
            [owner setValue:[NSValue valueWithCGPoint:CGPointZero] forKey:@"accumulatedAcceleration"];
            CGPoint raw=CGPointZero, accumulated=CGPointZero; NSMutableArray *steps=[NSMutableArray new];
            CGPoint deltas[]={{.25,0},{.5,0},{1,0},{2,0},{4,0},{0,4},{-3,-4},{-8,0},{.1,-.1},{0,0},{10,12},{-10,-12}};
            for(unsigned i=0;i<sizeof(deltas)/sizeof(deltas[0]);i++) {
                CGPoint d=deltas[i];raw.x+=d.x;raw.y+=d.y;BOOL active=i!=11;
                double gain=active?reconstructedGain(hypot(d.x,d.y)):0;
                accumulated.x+=d.x*gain;accumulated.y+=d.y*gain;
                CGPoint expected=CGPointMake(raw.x+accumulated.x,raw.y+accumulated.y);
                // Deliberately unrelated velocities test whether this implementation
                // uses the velocity argument rather than per-call displacement.
                CGPoint velocity=CGPointMake(i*1111.0,-(double)i*777.0);
                CGPoint native=((CGPoint(*)(id,SEL,CGPoint,CGPoint,BOOL))objc_msgSend)(interaction,sel_registerName("acceleratedTranslation:velocity:isActive:"),raw,velocity,active);
                [steps addObject:@{@"raw":pointJSON(raw),@"velocity":pointJSON(velocity),@"active":@(active),@"native":pointJSON(native),@"expected":pointJSON(expected)}];
                if(!nearPoint(native,expected))[failures addObject:[NSString stringWithFormat:@"acceleration step=%u",i]];
                [owner setValue:[NSValue valueWithCGPoint:raw] forKey:@"lastPanTranslation"];
            }
            result[@"acceleration"]=steps;
        } @finally {for(NSString *key in saved)[owner setValue:saved[key] forKey:key];}
        // Exercise native accumulation against a controlled boundary provider.
        ProbeBoundaryDelegate *boundaryDelegate=[ProbeBoundaryDelegate new];
        boundaryDelegate.textSelectionController=[ProbeBoundaryController new];
        id boundaryOwner=[NSClassFromString(@"_UIKeyboardTextSelectionGestureController") new];
        [boundaryOwner setValue:boundaryDelegate forKey:@"delegate"];
        id boundaryInteraction=((id(*)(id,SEL,id,id,NSInteger))objc_msgSend)([NSClassFromString(@"_UIKeyboardTextSelectionInteraction") alloc],sel_registerName("initWithView:owner:forTypes:"),nil,boundaryOwner,0);
        CGPoint corrections[]={{0,0},{5,-5},{3,-3},{-1,1},{-8,8},{0,0},{-9,9},{2,-2},{20,-20}};
        CGPoint accumulatedBounds=CGPointZero;
        NSMutableArray *bounding=[NSMutableArray new];
        for(unsigned i=0;i<sizeof(corrections)/sizeof(corrections[0]);i++) {
            CGPoint correction=corrections[i];boundaryDelegate.textSelectionController.correction=correction;
            CGPoint raw=CGPointMake(i*3.0,i*2.0);
            accumulatedBounds=CGPointMake(reconstructedBounding(accumulatedBounds.x,correction.x),reconstructedBounding(accumulatedBounds.y,correction.y));
            CGPoint expected=CGPointMake(raw.x+accumulatedBounds.x,raw.y+accumulatedBounds.y);
            CGPoint native=((CGPoint(*)(id,SEL,CGPoint))objc_msgSend)(boundaryInteraction,sel_registerName("boundedTranslation:"),raw);
            [bounding addObject:@{@"raw":pointJSON(raw),@"correction":pointJSON(correction),@"native":pointJSON(native),@"expected":pointJSON(expected)}];
            if(!nearPoint(native,expected))[failures addObject:[NSString stringWithFormat:@"bounding step=%u",i]];
        }
        result[@"bounding"]=bounding;
        // A fixed geometry fixture executes the unmodified native positioning
        // method. It is intentionally not a claim of an end-to-end touch test.
        ProbeSelectionManager *manager=[ProbeSelectionManager new];
        manager.textInput=[[ProbeClipView alloc] initWithFrame:CGRectMake(0,0,200,100)];
        manager.cursor=[[UIView alloc] initWithFrame:CGRectMake(100,40,2,20)];
        UIView *floating=[[UIView alloc] initWithFrame:CGRectMake(0,0,2,20)];
        id session=class_createInstance(NSClassFromString(@"_UITextFloatingCursorSession"),0);
        [session setValue:manager forKey:@"manager"];
        [session setValue:floating forKey:@"floatingCursorView"];
        CGPoint points[]={{-20,-20},{1,10},{100,25},{100,40},{100,50},{100,75},{199,90},{250,130}};
        NSMutableArray *positions=[NSMutableArray new];
        for(int snap=0;snap<=1;snap++) for(unsigned i=0;i<sizeof(points)/sizeof(points[0]);i++) {
            CGPoint p=points[i];CGPoint expected=CGPointMake(fmin(199,fmax(1,p.x)),fmin(90,fmax(10,p.y)));
            if(snap)expected.y=50+0.3*(expected.y-50);
            CGPoint native=((CGPoint(*)(id,SEL,CGPoint,BOOL))objc_msgSend)(session,sel_registerName("floatingCursorPositionForPoint:lineSnapping:"),p,(BOOL)snap);
            [positions addObject:@{@"input":pointJSON(p),@"lineSnapping":@(snap),@"native":pointJSON(native),@"expected":pointJSON(expected)}];
            if(!nearPoint(native,expected))[failures addObject:[NSString stringWithFormat:@"floating point=%u snap=%d",i,snap]];
        }
        result[@"floatingCursor"]=positions;
        // Probe geometry resolution in a real UITextView without showing it or
        // replacing text in the user's editor.
        UITextView *editor=[[UITextView alloc] initWithFrame:CGRectMake(0,0,260,300)];
        editor.font=[UIFont systemFontOfSize:22];
        editor.text=@"The quick brown fox jumps over the lazy dog.\nРусский ө ү ё\n👨‍👩‍👧‍👦 🇲🇳 é";
        [editor layoutIfNeeded];
        id controller=((id(*)(id,SEL,id))objc_msgSend)([NSClassFromString(@"_UIKeyboardTextSelectionController") alloc],sel_registerName("initWithInputDelegate:"),editor);
        CGPoint targets[]={{20,20},{100,20},{200,20},{100,45},{100,70},{100,95},{100,120},{100,145},{-100,-100},{1000,1000}};
        NSMutableArray *selections=[NSMutableArray new];
        for(unsigned i=0;i<sizeof(targets)/sizeof(targets[0]);i++) {
            CGPoint p=targets[i];
            UITextPosition *closest=[editor closestPositionToPoint:p];
            NSInteger expected=[editor offsetFromPosition:editor.beginningOfDocument toPosition:closest];
            ((void(*)(id,SEL,CGPoint,NSInteger,id))objc_msgSend)(controller,sel_registerName("selectPositionAtPoint:granularity:completionHandler:"),p,0,nil);
            NSUInteger actual=editor.selectedRange.location;
            CGRect caret=[editor caretRectForPosition:editor.selectedTextRange.end];
            [selections addObject:@{@"point":pointJSON(p),@"selectedUTF16Offset":@(actual),@"closestUTF16Offset":@(expected),@"caret":NSStringFromCGRect(caret)}];
            if(actual!=expected)[failures addObject:[NSString stringWithFormat:@"selection point=%u native=%lu closest=%ld",i,(unsigned long)actual,(long)expected]];
        }
        result[@"selectionGeometry"]=selections;
        NSMutableIndexSet *boundaries=[NSMutableIndexSet indexSetWithIndex:0];
        [editor.text enumerateSubstringsInRange:NSMakeRange(0,editor.text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring,NSRange range,NSRange enclosingRange,BOOL *stop) {
            [boundaries addIndex:NSMaxRange(range)];
        }];
        NSUInteger unicodeCases=0;
        for(int y=20;y<=95;y+=25) for(int x=0;x<=260;x+=2) {
            ((void(*)(id,SEL,CGPoint,NSInteger,id))objc_msgSend)(controller,sel_registerName("selectPositionAtPoint:granularity:completionHandler:"),CGPointMake(x,y),0,nil);
            unicodeCases++;
            if(![boundaries containsIndex:editor.selectedRange.location])[failures addObject:[NSString stringWithFormat:@"non-grapheme selection at %lu",(unsigned long)editor.selectedRange.location]];
        }
        result[@"unicodeGeometryCases"]=@(unicodeCases);
        // Seed the native history object with deterministic timestamps. Runtime
        // layout is checked before touching this isolated fixture's C array.
        Class historyClass=NSClassFromString(@"UITextMagnifierTimeWeightedPoint");
        Ivar pointsIvar=class_getInstanceVariable(historyClass,"m_points");
        Ivar indexIvar=class_getInstanceVariable(historyClass,"m_index");
        typedef struct {CGPoint point;double time;} HistorySample;
        if(!pointsIvar||!indexIvar||strcmp(ivar_getTypeEncoding(pointsIvar),"[16{?=\"point\"{CGPoint=\"x\"d\"y\"d}\"time\"d}]")!=0) {
            [failures addObject:@"native history layout changed"];
        } else {
            id history=[historyClass new];NSMutableArray *historyCases=[NSMutableArray new];
            const double ages[2][4]={{.4,.25,.08,0},{.10,.07,.03,0}};
            for(int shortHistory=0;shortHistory<=1;shortHistory++) {
                ((void(*)(id,SEL))objc_msgSend)(history,sel_registerName("clearHistory"));double now=CFAbsoluteTimeGetCurrent();
                HistorySample samples[16];
                for(int i=0;i<16;i++)samples[i]=(HistorySample){CGPointZero,-1};
                for(int i=0;i<4;i++)samples[i]=(HistorySample){CGPointMake(10+i*10,20+i*10),now-ages[shortHistory][i]};
                char *bytes=(char *)(__bridge void *)history;
                memcpy(bytes+ivar_getOffset(pointsIvar),samples,sizeof(samples));
                int index=4;memcpy(bytes+ivar_getOffset(indexIvar),&index,sizeof(index));
                CGPoint native=((CGPoint(*)(id,SEL))objc_msgSend)(history,sel_registerName("weightedPoint"));
                CGPoint expected=shortHistory?CGPointMake(40,50):CGPointMake(20,30);
                [historyCases addObject:@{@"shortHistory":@(shortHistory),@"native":pointJSON(native),@"expected":pointJSON(expected)}];
                if(!nearPoint(native,expected))[failures addObject:[NSString stringWithFormat:@"history short=%d",shortHistory]];
            }
            result[@"releaseHistory"]=historyCases;
        }
    } @catch(NSException *e) {[failures addObject:[NSString stringWithFormat:@"exception %@: %@",e.name,e.reason]];}
    result[@"failures"]=failures;result[@"passed"]=@(failures.count==0);
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
    printf("NATIVE_MEASUREMENTS %s\n",[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);fflush(stdout);
    return failures.count==0;
}
