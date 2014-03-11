//
//  WIImageTarget.h
//  VuforiaTargets
//
//  Created by Paul Wood on 3/11/14.
//  Copyright (c) 2014 Walkin. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface WIImageTarget : NSObject

@property BOOL isSelected;
@property (strong) NSNumber *starRating;
@property (strong) NSString *imageString;
@property (strong) NSString *featureImageString;
@property (strong) NSString *datString;
@property (strong) NSString *xmlString;

+ (id)imageTargetWithDictionary:(NSDictionary *)dict;
- (UIImage *)image;
- (UIImage *)featureImage;

@end