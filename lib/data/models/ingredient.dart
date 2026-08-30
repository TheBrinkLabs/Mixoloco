import 'package:flutter/material.dart';

/// A single throwable ingredient — a glass/jug of something specific
/// (e.g. "lime juice", "blue curaçao"). Levels spawn a pool of these on
/// the bar; the player throws matching sets down to the serving end to
/// fulfil the current order. [color] is a placeholder stand-in for real
/// art until ingredient sprites exist.
class Ingredient {
  final String id;
  final String label;
  final Color color;

  const Ingredient({required this.id, required this.label, required this.color});
}

/// Starter ingredient set for the first ("dodgy bar") tier — deliberately
/// small and basic; later bar tiers unlock more exotic ingredients as the
/// player progresses (see CocktailRecipe/level design).
const kTier1Ingredients = [
  Ingredient(id: 'lime', label: 'Lime Juice', color: Color(0xFF9ACD32)),
  Ingredient(id: 'orange', label: 'Orange Juice', color: Color(0xFFFFA500)),
  Ingredient(id: 'cola', label: 'Cola', color: Color(0xFF3B1F0E)),
  Ingredient(id: 'soda', label: 'Soda Water', color: Color(0xFFE8F6F6)),
  Ingredient(id: 'rum', label: 'Rum', color: Color(0xFFC48A3E)),
];
