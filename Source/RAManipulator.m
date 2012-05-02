//
//  RAManipulator.m
//  RASceneGraphTest
//
//  Created by Ross Anderson on 3/4/12.
//  Copyright (c) 2012 Ross Anderson. All rights reserved.
//

#import "RAManipulator.h"

#import "TPPropertyAnimation.h"

//#define ENABLE_DEBUG_GESTURES

static const RAPolarCoordinate kFreshPondCoord = { 42.384733, -71.149392, 1e7 };
static const RAPolarCoordinate kPolarNone = { -1, -1, -1 };
static const RAPolarCoordinate kPolarZero = { 0, 0, 0 };
static const RAPolarCoordinate kDefaultVelocity = { 0, -10, 0 };

static const CGFloat kAnimationDuration = 1.0f;
static const CGFloat kMinimumAnimatedAngle = 2.0f;
static const double kMaximumLatitude = 85.;


typedef struct {
    double  latitude;      // all angles in degrees
    double  longitude;
    double  azimuth;
    double  elevation;
    double  distance;
} CameraState;

typedef enum {
    GestureNone = 0,
    GestureGeoDrag,
    GestureAxisSpin,
    GestureRotate,
    GestureTilt
} GestureAction;


@implementation RAManipulator {
    CameraState     _state;
    
    UIView *        _view;
}

@synthesize camera;

- (id)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (UIView *)view {
    return _view;
}

- (void)setView:(UIView *)view {
    _view = view;
    
    self.latitude = kFreshPondCoord.latitude;
    self.longitude = kFreshPondCoord.longitude;
    self.distance = kFreshPondCoord.height;
    self.azimuth = 0;
    self.elevation = 90;
    
    // add gestures
    UIPinchGestureRecognizer * pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(scale:)];
	[pinchRecognizer setDelegate:self];
	[view addGestureRecognizer:pinchRecognizer];
    
	UIPanGestureRecognizer * panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(move:)];
	[panRecognizer setDelegate:self];
	[view addGestureRecognizer:panRecognizer];
    
	UITapGestureRecognizer * zoomRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(zoomToLocation:)];
	[zoomRecognizer setNumberOfTapsRequired:2];
	[zoomRecognizer setDelegate:self];
	[view addGestureRecognizer:zoomRecognizer];
    
	UITapGestureRecognizer * stopRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(stop:)];
	[stopRecognizer setNumberOfTapsRequired:1];
	[stopRecognizer setDelegate:self];
	[view addGestureRecognizer:stopRecognizer];
    
#ifdef ENABLE_DEBUG_GESTURES
	UITapGestureRecognizer * worldTourRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(debugWorldTour:)];
	[worldTourRecognizer setNumberOfTapsRequired:4];
	[worldTourRecognizer setDelegate:self];
	[view addGestureRecognizer:worldTourRecognizer];
#endif
}

- (double)latitude {
    return _state.latitude;
}

- (void)setLatitude:(double)latitude {
    NSAssert( !isnan(latitude), @"angle cannot be NAN" );
    latitude = fmod( latitude, 360. );
    _state.latitude = latitude;
}

- (double)longitude {
    return _state.longitude;
}

- (void)setLongitude:(double)longitude {
    NSAssert( !isnan(longitude), @"angle cannot be NAN" );
    longitude = fmod( longitude, 360. );
    if ( longitude < 0.0 ) longitude += 360.;
    
    _state.longitude = longitude;
}

- (double)azimuth {
    return _state.azimuth;
}

- (void)setAzimuth:(double)azimuth {
    NSAssert( !isnan(azimuth), @"angle cannot be NAN" );
    azimuth = fmod( azimuth, 360. );
    _state.azimuth = azimuth;
}

- (double)elevation {
    return _state.elevation;
}

- (void)setElevation:(double)elevation {
    NSAssert( !isnan(elevation), @"angle cannot be NAN" );
    if ( elevation < 0 ) elevation = 0;
    if ( elevation > 90 ) elevation = 90;
    _state.elevation = elevation;
}

- (double)distance {
    return _state.distance;
}

- (void)setDistance:(double)distance {
    NSAssert( !isnan(distance), @"distance cannot be NAN" );
    if ( distance < 200. ) distance = 200.;
    _state.distance = distance;
}

/*
- (NSString *)stringFromMatrix:(GLKMatrix4)m {
    return [NSString stringWithFormat:@"%f %f %f %f,\n%f %f %f %f,\n%f %f %f %f,\n%f %f %f %f",
            m.m00, m.m01, m.m02, m.m03,
            m.m10, m.m11, m.m12, m.m13,
            m.m20, m.m21, m.m22, m.m23,
            m.m30, m.m31, m.m32, m.m33];
}
*/

- (GLKMatrix4)modelViewMatrixForState:(CameraState)aState {
    RAPolarCoordinate   surfaceCoord = { self.latitude, self.longitude, 0 };
    GLKVector3          surfacePos = ConvertPolarToEcef(surfaceCoord);
    
    GLKMatrix4 surfaceTransform = GLKMatrix4MakeLookAt(surfacePos.x, surfacePos.y, surfacePos.z, 0, 0, 0, 0, 0, 1);
    
    GLKMatrix4 perspective = GLKMatrix4Identity;
    perspective = GLKMatrix4Translate(perspective, 0, 0, ConvertHeightToEcef(-self.distance));
    perspective = GLKMatrix4Rotate(perspective,  (90.-self.elevation) * (M_PI/180.), -1, 0, 0);
    perspective = GLKMatrix4Rotate(perspective, self.azimuth * (M_PI/180.), 0, 0, 1);
    
    GLKMatrix4 modelView = GLKMatrix4Multiply(perspective, surfaceTransform);
    //NSLog(@"ModelView: %@", [self stringFromMatrix:renderVisitor.projectionMatrix], [self stringFromMatrix:modelView]);

    return modelView;
}

- (BOOL)intersectPoint:(CGPoint)point atLatitude:(double*)lat atLongitude:(double*)lon withState:(CameraState)aState
{
    GLKVector3 swin = { point.x, point.y, 0 };
    GLKVector3 ewin = { point.x, point.y, 1 };
    int        viewport[4] = { self.camera.viewport.origin.x, self.camera.viewport.origin.y + self.camera.viewport.size.height, self.camera.viewport.size.width, -self.camera.viewport.size.height };
    GLKMatrix4 modelViewMatrix = [self modelViewMatrixForState:aState];
        
    bool startValid, endValid;
    GLKVector3 start = GLKMathUnproject ( swin, modelViewMatrix, self.camera.projectionMatrix, viewport, &startValid );
    GLKVector3 end = GLKMathUnproject ( ewin, modelViewMatrix, self.camera.projectionMatrix, viewport, &endValid );
    
    if ( startValid && endValid ) {
        // find intersection
        GLKVector3 position;
        if ( IntersectWithEllipsoid( start, end, &position ) ) {
            RAPolarCoordinate coord = ConvertEcefToPolar(position);
            if ( lat ) *lat = coord.latitude;
            if ( lon ) *lon = coord.longitude;
            return YES;
        }
    }
    
    return NO;
}

- (GLKMatrix4)modelViewMatrix {
    return [self modelViewMatrixForState:_state];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    // allow user to pan and zoom at the same time
    if ( [gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]] && [otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] )
        return YES;
    
    return NO;
}

- (void)scale:(id)sender {
    UIPinchGestureRecognizer * pinch = (UIPinchGestureRecognizer*)sender;
    
    static CameraState startState;
    static CGFloat startScale = 1;
    
    switch( [pinch state] ) {
        case UIGestureRecognizerStatePossible:
            break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            _state = startState;
            break;
        case UIGestureRecognizerStateBegan:
            [self stop:nil];

            startState = _state;
            startScale = pinch.scale;
            break;
        case UIGestureRecognizerStateChanged:
        {
            CGFloat ds = startScale / pinch.scale;
            self.distance = ds * startState.distance;
            
            //NSLog(@"distance = %f", _state.distance);
            break;
        }
        case UIGestureRecognizerStateEnded:
        {
            /*
            // calculate how much movement
            CGFloat distance = _state.distance / pinch.velocity;
            if ( fabs(distance) < _state.distance / 10. ) break;
            
            TPPropertyAnimation *anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"distance"];
            anim.duration = kAnimationDuration;
            anim.fromValue = [NSNumber numberWithDouble:_state.distance];
            anim.toValue = [NSNumber numberWithDouble:_state.distance - distance];
            anim.timing = TPPropertyAnimationTimingEaseOut;
            [anim beginWithTarget:self];
            */
            break;
        }
    }
}

- (void)move:(id)sender {
    UIPanGestureRecognizer * pan = (UIPanGestureRecognizer*)sender;
    
    static GestureAction sAction;
    static CGPoint startLocation;
    static CameraState startState;
    static double cursorLatitude, cursorLongitude;
    static int touchCount;
    
    CGPoint pt = [pan locationInView:self.view];

    switch( [pan state] ) {
        case UIGestureRecognizerStatePossible:
            break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            _state = startState;
            break;
        case UIGestureRecognizerStateBegan:
        {
            [self stop:nil];

            CGFloat yThresh = self.view.bounds.size.height / 10.;
            CGFloat xThresh = self.view.bounds.size.width / 10.;

            // pick the right gesture
            if ( pt.y > self.view.bounds.size.height - yThresh ) 
                sAction = GestureRotate;
            else if ( pt.x > self.view.bounds.size.width - xThresh )
                sAction = GestureTilt;
            else {
                // get the current touch position on the globe
                if ( [self intersectPoint:pt atLatitude:&cursorLatitude atLongitude:&cursorLongitude withState:_state] )
                    sAction = GestureGeoDrag;
                else
                    sAction = GestureAxisSpin;
            }
                        
            startLocation = pt;
            startState = _state;
            touchCount = [pan numberOfTouches];
            break;
        }
        case UIGestureRecognizerStateChanged:
        {
            // ignore change if it's because one of the fingers lifted
            if ( [pan numberOfTouches] != touchCount ) {
                break;
            }
            
            switch (sAction) {
                case GestureRotate:
                {
                    double angle = ( pt.x - startLocation.x ) * 0.1;
                    self.azimuth = startState.azimuth + angle;
                    break;
                }
                case GestureTilt:
                {
                    double angle = ( pt.y - startLocation.y ) * 0.1;
                    self.elevation = startState.elevation + angle;
                    break;
                }
                case GestureGeoDrag:
                {
                    double lat, lon;
                    if ( [self intersectPoint:pt atLatitude:&lat atLongitude:&lon withState:_state] ) {
                        // rotate the globe so cursor is under the touch again
                        self.latitude -= lat - cursorLatitude;
                        self.longitude -= lon - cursorLongitude;
                        
                        if ( _state.latitude > kMaximumLatitude ) self.latitude = kMaximumLatitude;
                        if ( _state.latitude < -kMaximumLatitude ) self.latitude = -kMaximumLatitude;
                        
                        //NSLog(@"lat = %f, lon = %f", _state.latitude, _state.longitude);
                    }
                    break;
                }
                case GestureAxisSpin:
                {
                    double angle = -( pt.x - startLocation.x ) * 0.1;
                    self.longitude = startState.longitude + angle;
                    break;
                }
                case GestureNone: break;
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        {
            CGPoint vel = [pan velocityInView:self.view];
            
            switch (sAction) {
                case GestureRotate:
                {
                    // calculate how much movement
                    CGFloat angle = vel.x * 0.03;
                    if ( fabs(angle) < kMinimumAnimatedAngle ) break;

                    TPPropertyAnimation *anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"azimuth"];
                    anim.duration = kAnimationDuration;
                    anim.fromValue = [NSNumber numberWithDouble:_state.azimuth];
                    anim.toValue = [NSNumber numberWithDouble:_state.azimuth + angle];
                    anim.timing = TPPropertyAnimationTimingEaseOut;
                    [anim beginWithTarget:self];
                    break;
                }
                case GestureTilt:
                {
                    // calculate how much movement
                    CGFloat angle = vel.y * 0.03;
                    if ( fabs(angle) < kMinimumAnimatedAngle ) break;
                    
                    TPPropertyAnimation *anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"elevation"];
                    anim.duration = kAnimationDuration;
                    anim.fromValue = [NSNumber numberWithDouble:_state.elevation];
                    anim.toValue = [NSNumber numberWithDouble:_state.elevation + angle];
                    anim.timing = TPPropertyAnimationTimingEaseOut;
                    [anim beginWithTarget:self];
                    break;
                }
                case GestureGeoDrag:
                {
                    // continue movement in the same direction
                    CGPoint dir = CGPointMake( _state.longitude - startState.longitude, _state.latitude - startState.latitude );
                    if ( dir.x > 180. ) dir.x -= 360.;
                    if ( dir.x < -180. ) dir.x += 360.;

                    CGFloat length = sqrt( dir.x*dir.x + dir.y*dir.y );
                    if ( length < 1 ) break;
                    dir.x /= length;
                    dir.y /= length;
                    
                    // calculate how much movement
                    CGFloat speed = sqrt( vel.x*vel.x + vel.y*vel.y );
                    CGFloat angle = ( _state.distance / 1e7 ) * speed * 0.03;
                    if ( fabs(angle) < kMinimumAnimatedAngle ) break;
                    
                    CGPoint destination = CGPointMake( _state.longitude + dir.x*angle, _state.latitude + dir.y*angle );
                    /*if ( destination.y > kMaximumLatitude ) destination.y = kMaximumLatitude;
                    if ( destination.y < -kMaximumLatitude ) destination.y = -kMaximumLatitude;*/
                    
                    // zoom to that location
                    TPPropertyAnimation *anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"latitude"];
                    anim.duration = kAnimationDuration;
                    anim.fromValue = [NSNumber numberWithDouble:_state.latitude];
                    anim.toValue = [NSNumber numberWithDouble:destination.y];
                    anim.timing = TPPropertyAnimationTimingEaseOut;
                    [anim beginWithTarget:self];
                    
                    anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"longitude"];
                    anim.duration = kAnimationDuration;
                    anim.fromValue = [NSNumber numberWithDouble:_state.longitude];
                    anim.toValue = [NSNumber numberWithDouble:destination.x];
                    anim.timing = TPPropertyAnimationTimingEaseOut;
                    [anim beginWithTarget:self];
                    
                    break;
                }
                case GestureAxisSpin:
                {
                    // calculate how much movement
                    CGFloat speed = vel.x;
                    CGFloat angle = -( _state.distance / 1e7 ) * speed * 0.1;
                    if ( fabs(angle) < kMinimumAnimatedAngle ) break;
                    
                    float destination = _state.longitude + angle;
                    
                    // spin the globe
                    TPPropertyAnimation *anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"longitude"];
                    anim.duration = kAnimationDuration * 2.0;
                    anim.fromValue = [NSNumber numberWithDouble:_state.longitude];
                    anim.toValue = [NSNumber numberWithDouble:destination];
                    anim.timing = TPPropertyAnimationTimingEaseOut;
                    [anim beginWithTarget:self];
                    
                    break;
                }
                case GestureNone: break;
            }
            
            sAction = GestureNone;
            break;
        }
    }
}

- (void)stop:(id)sender {
    // cancel animations in progress
    [[TPPropertyAnimation allPropertyAnimationsForTarget:self] makeObjectsPerformSelector:@selector(cancel)];

    //printf("Stop\n");
}

- (void)zoomToLocation:(id)sender {
    UITapGestureRecognizer * tap = (UITapGestureRecognizer*)sender;
    
    CGPoint pt = [tap locationInView:self.view];
    double lat, lon;
    
    // get the current touch position on the globe
    [self intersectPoint:pt atLatitude:&lat atLongitude:&lon withState:_state];
    
    //printf("Zoom to: %f, %f\n", lat, lon);
    
    double duration = 1.0;

    // zoom in to that location
    TPPropertyAnimation *anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"latitude"];
    anim.duration = duration;
    anim.fromValue = [NSNumber numberWithDouble:_state.latitude];
    anim.toValue = [NSNumber numberWithDouble:lat];
    anim.timing = TPPropertyAnimationTimingEaseInEaseOut;
    [anim beginWithTarget:self];

    anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"longitude"];
    anim.duration = duration;
    anim.fromValue = [NSNumber numberWithDouble:_state.longitude];
    anim.toValue = [NSNumber numberWithDouble:lon];
    anim.timing = TPPropertyAnimationTimingEaseInEaseOut;
    [anim beginWithTarget:self];

    anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"distance"];
    anim.duration = duration;
    anim.fromValue = [NSNumber numberWithDouble:_state.distance];
    anim.toValue = [NSNumber numberWithDouble:_state.distance / 2.0];
    anim.timing = TPPropertyAnimationTimingEaseInEaseOut;
    [anim beginWithTarget:self];
    
    //NSLog(@"Zoom from %@ to %@", anim.fromValue, anim.toValue);
}

- (void)debugWorldTour:(id)sender {
    // rotate slowly along line of constant latitude
    double duration = 12.*3600.;    // around the world in twelve short hours
    
    TPPropertyAnimation *anim = [TPPropertyAnimation propertyAnimationWithKeyPath:@"longitude"];
    anim.duration = duration;
    anim.fromValue = [NSNumber numberWithDouble:_state.longitude];
    anim.toValue = [NSNumber numberWithDouble:_state.longitude+360];
    anim.timing = TPPropertyAnimationTimingLinear;
    [anim beginWithTarget:self];
}

@end
