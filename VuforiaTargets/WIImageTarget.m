//
//  WIImageTarget.m
//  VuforiaTargets
//
//  Created by Paul Wood on 3/11/14.
//  Copyright (c) 2014 Walkin. All rights reserved.
//

#import "WIImageTarget.h"

@implementation WIImageTarget

+ (id)imageTargetWithDictionary:(NSDictionary *)dict{
    WIImageTarget *target = [[WIImageTarget alloc] init];
    target.imageString = [dict objectForKey:@"image"];
    target.featureImageString = [dict objectForKey:@"featureImage"];
    target.datString = [dict objectForKey:@"dat"];
    target.xmlString = [dict objectForKey:@"xml"];
    target.starRating = [dict objectForKey:@"rating"];
    target.isSelected = YES;
    return target;
}

- (UIImage *)image{
    UIImage *returnImage = [UIImage imageNamed:self.imageString];
    return returnImage;
}

- (UIImage *)featureImage{
    UIImage *returnImage = [UIImage imageNamed:self.featureImageString];
    return returnImage;
}

- (NSString *)description{
    return [NSString stringWithFormat:@"< %@ | image:%@ | rating:%f | featureImage:%@ | dat:%@ | xml:%@ >",
            [self class],
            self.imageString,
            [self.starRating floatValue],
            self.featureImageString,
            self.datString,
            self.xmlString];
}

@end